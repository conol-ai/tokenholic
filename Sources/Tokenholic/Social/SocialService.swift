import Foundation
import Combine
import Supabase

/// Friends + daily leaderboard, layered on the same Supabase backend as
/// `SupabaseSync`. A structural twin of `SupabaseSync`: `@MainActor`
/// `ObservableObject`, `@Published private(set)` outputs, a 45s poll, and a 10s
/// debounce on the daily-value write.
///
/// It does NOT drive `authStateChanges` (SupabaseSync already does); `AppModel`
/// forwards sign-in/out via `onAuthChanged(isSignedIn:)`. Every cross-user read
/// goes through a friendship-gated SECURITY DEFINER RPC — the client never does
/// a raw cross-user SELECT.
@MainActor
final class SocialService: ObservableObject {
    @Published private(set) var available = false
    @Published private(set) var isSignedIn = false
    @Published private(set) var profile: ProfileRow?
    @Published private(set) var shareDaily = true
    @Published private(set) var friends: [FriendRow] = []
    @Published private(set) var incomingRequests: [RequestRow] = []
    @Published private(set) var outgoingRequests: [RequestRow] = []
    @Published private(set) var leaderboard: [LeaderboardRow] = []
    @Published private(set) var currentInvite: InviteRow?
    /// Unified transient message channel (info + error) for the UI toast.
    @Published private(set) var toast: SocialToast?

    private let client: SupabaseClient?
    private var pollTimer: Timer?
    private var writeItem: DispatchWorkItem?
    private var pendingDaily: [DailyValueWrite] = []
    /// An invite code received while signed out; redeemed once a session exists.
    private var pendingInviteCode: String?
    private var toastSeq = 0
    private let writeDebounce: TimeInterval = 10
    private let pollInterval: TimeInterval = 45
    private var leaderboardDay: String = SocialService.todayKey()

    init(env: SupabaseEnvironment) {
        client = env.client
        available = env.available
    }

    /// SocialService observes nothing directly; AppModel pipes shared auth in.
    func start() {}

    /// Shared auth state, forwarded from `SupabaseSync.$isSignedIn` by AppModel.
    func onAuthChanged(isSignedIn: Bool) {
        self.isSignedIn = isSignedIn
        guard available else { return }
        if isSignedIn {
            startPolling()
            refreshAll()
            flushDaily()                 // push whatever we already computed
            if let code = pendingInviteCode {   // a link clicked while signed out
                pendingInviteCode = nil
                performRedeem(code)
            }
        } else {
            profile = nil; shareDaily = true
            friends = []; incomingRequests = []; outgoingRequests = []
            leaderboard = []; currentInvite = nil
            pollTimer?.invalidate(); pollTimer = nil
        }
    }

    // MARK: - Profile / handle / privacy toggle

    /// Claim or rename the caller's @handle (the social opt-in). The server
    /// captures the trusted GitHub login itself; `displayName` is a nicety.
    func claimHandle(_ handle: String, displayName: String?) {
        guard let client else { return }
        let h = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                _ = try await client.rpc("claim_handle", params: ClaimHandleParams(
                    p_handle: h,
                    p_display_name: (displayName?.isEmpty ?? true) ? nil : displayName,
                    p_avatar_url: nil
                )).execute()
                report("You're @\(h)", isError: false)
                await loadProfile()
                refreshLeaderboard()
            } catch {
                report(Self.friendly(error), isError: true)
            }
        }
    }

    /// Optimistically flip the share toggle, then persist. Reverts on failure —
    /// but only if a newer toggle hasn't superseded this one.
    func setShareDaily(_ on: Bool) {
        guard let client else { return }
        let previous = shareDaily
        shareDaily = on
        Task {
            do {
                _ = try await client.rpc("set_share_preference",
                                         params: SharePrefParams(p_share: on)).execute()
                await loadProfile()
                refreshLeaderboard()
            } catch {
                if shareDaily == on { shareDaily = previous }   // don't clobber a newer toggle
                report(Self.friendly(error), isError: true)
            }
        }
    }

    // MARK: - Friends & requests

    /// Add by @handle: look the handle up, then send a consent-based request.
    func sendRequest(toHandle handle: String) {
        guard let client else { return }
        let norm = handle.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        guard norm.count >= 3 else { report("Handles are at least 3 characters.", isError: true); return }
        Task {
            do {
                let hits: [HandleHit] = try await client.rpc(
                    "lookup_profile_by_handle", params: HandleParam(p_handle: norm)).execute().value
                guard let hit = hits.first else {
                    report("No one is using @\(norm).", isError: true)
                    return
                }
                await sendRequestAwait(toUserId: hit.user_id, handle: norm)
            } catch {
                report(Self.friendly(error), isError: true)
            }
        }
    }

    func sendRequest(toUserId id: String) {
        Task { await sendRequestAwait(toUserId: id, handle: nil) }
    }

    private func sendRequestAwait(toUserId id: String, handle: String?) async {
        guard let client else { return }
        do {
            _ = try await client.rpc("send_friend_request",
                                     params: AddresseeParam(p_addressee: id)).execute()
            report(handle.map { "Request sent to @\($0)" } ?? "Request sent", isError: false)
            loadFriendsAndRequests()
            refreshLeaderboard()
        } catch {
            report(Self.friendly(error), isError: true)
        }
    }

    func acceptRequest(_ requestId: String) {
        mutate("accept_friend_request", RequestIdParam(p_request_id: requestId), info: "Friend added")
    }
    func declineRequest(_ requestId: String) {
        mutate("decline_friend_request", RequestIdParam(p_request_id: requestId), info: nil)
    }
    func removeFriend(_ userId: String) {
        mutate("remove_friend", OtherParam(p_other: userId), info: "Friend removed")
    }
    func blockUser(_ userId: String) {
        mutate("block_user", OtherParam(p_other: userId), info: "Blocked")
    }

    private func mutate(_ fn: String, _ params: some Encodable, info: String?) {
        guard let client else { return }
        Task {
            do {
                _ = try await client.rpc(fn, params: params).execute()
                if let info { report(info, isError: false) }
                loadFriendsAndRequests()
                refreshLeaderboard()
            } catch {
                report(Self.friendly(error), isError: true)
            }
        }
    }

    // MARK: - Invites

    /// Generate (or rotate to) a fresh single-use, 24h invite link.
    func createInvite() {
        guard let client else { return }
        Task {
            do {
                _ = try await client.rpc("rotate_invite").execute()
                await loadInvite()
                report("New invite link ready", isError: false)
            } catch {
                report(Self.friendly(error), isError: true)
            }
        }
    }

    /// Redeem a pasted code or full invite link. If signed out (e.g. a cold
    /// launch from a link), stash it and redeem once a session exists.
    func redeemInvite(code rawInput: String) {
        guard let code = InviteURL.extractCode(fromUserInput: rawInput) else {
            report("That doesn't look like an invite code.", isError: true)
            return
        }
        guard isSignedIn else {
            pendingInviteCode = code
            report("Sign in to accept this invite.", isError: false)
            return
        }
        performRedeem(code)
    }

    private func performRedeem(_ code: String) {
        guard let client else { return }
        Task {
            do {
                let res: [RedeemResult] = try await client.rpc(
                    "redeem_invite", params: CodeParam(p_code: code)).execute().value
                if let friend = res.first {
                    report("Now friends with @\(friend.friend_handle ?? "your invite")", isError: false)
                } else {
                    report("Request sent — they'll confirm it.", isError: false)
                }
                loadFriendsAndRequests()
                refreshLeaderboard()
            } catch {
                report(Self.friendly(error), isError: true)
            }
        }
    }

    // MARK: - Leaderboard

    func setLeaderboardDay(_ key: String) {
        leaderboardDay = key
        refreshLeaderboard()
    }

    func refreshLeaderboard() {
        guard let client, isSignedIn else { return }
        let day = leaderboardDay
        Task {
            do {
                let rows: [LeaderboardRow] = try await client.rpc(
                    "leaderboard_for_day", params: DayParam(p_day: day)).execute().value
                leaderboard = rows
            } catch {
                report(Self.friendly(error), isError: true)
            }
        }
    }

    // MARK: - Daily API value push (called by AppModel on each recompute)

    func publishDaily(_ points: [DailyValueWrite]) {
        pendingDaily = points
        guard available, isSignedIn, !points.isEmpty else { return }
        writeItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in await self?.upsertDaily() }
        }
        writeItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + writeDebounce, execute: item)
    }

    func flushDaily() {
        writeItem?.cancel()
        guard available, isSignedIn, !pendingDaily.isEmpty else { return }
        Task { @MainActor in await upsertDaily() }
    }

    private func upsertDaily() async {
        guard let client, isSignedIn else { return }
        for row in pendingDaily {
            do {
                _ = try await client.rpc("upsert_daily_total", params: UpsertDailyParams(
                    p_device_id: row.device_id, p_day: row.day,
                    p_api_value: row.api_usd, p_tokens: row.tokens)).execute()
            } catch {
                // One out-of-window day shouldn't abort the rest; surface quietly.
                report(Self.friendly(error), isError: true)
            }
        }
        refreshLeaderboard()
    }

    // MARK: - Fetch

    private func refreshAll() {
        Task { await loadProfile() }
        loadFriendsAndRequests()
        refreshLeaderboard()
        Task { await loadInvite() }
    }

    private func loadProfile() async {
        guard let client, isSignedIn else { return }
        do {
            let rows: [ProfileRow] = try await client.from("profiles").select().execute().value
            profile = rows.first
            shareDaily = rows.first?.share_daily_total ?? true
        } catch {
            report(Self.friendly(error), isError: true)
        }
    }

    private func loadFriendsAndRequests() {
        guard let client, isSignedIn else { return }
        Task {
            do {
                let f: [FriendRow] = try await client.rpc("list_friends").execute().value
                friends = f
            } catch { report(Self.friendly(error), isError: true) }
            do {
                let r: [RequestRow] = try await client.rpc("list_requests").execute().value
                incomingRequests = r.filter { $0.isIncoming }
                outgoingRequests = r.filter { !$0.isIncoming }
            } catch { report(Self.friendly(error), isError: true) }
        }
    }

    private func loadInvite() async {
        guard let client, isSignedIn else { return }
        do {
            let rows: [InviteRow] = try await client.from("invite_codes").select().execute().value
            currentInvite = rows
                .filter { $0.isLive }
                .sorted { ($0.created_at ?? .distantPast) > ($1.created_at ?? .distantPast) }
                .first
        } catch {
            report(Self.friendly(error), isError: true)
        }
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.loadFriendsAndRequests()
                self?.refreshLeaderboard()
            }
        }
    }

    // MARK: - Helpers

    private func report(_ text: String, isError: Bool) {
        toastSeq += 1
        toast = SocialToast(text: text, isError: isError, seq: toastSeq)
    }

    /// Local-day "yyyy-MM-dd" — the SAME calendar/timezone that buckets
    /// `DailyPoint.day`, so a device reports its own local day.
    static func todayKey(_ now: Date = Date(), _ cal: Calendar = .current) -> String {
        let f = DateFormatter()
        f.calendar = cal
        f.timeZone = .current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: now)
    }

    /// Extract a human-readable message from a Postgrest error where possible.
    private static func friendly(_ error: Error) -> String {
        if let pg = error as? PostgrestError { return pg.message }
        return error.localizedDescription
    }
}
