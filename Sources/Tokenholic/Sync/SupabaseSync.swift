import Foundation
import Combine
import Supabase
import AuthenticationServices

/// Cross-device sync via a lightweight Supabase backend.
///
/// Each device upserts ONLY its own `(user_id, device_id)` row and reads all of
/// the signed-in user's rows to aggregate. RLS scopes everything to the user.
/// Mirrors the surface `AppModel` expects (`peers`, `available`, `publish`,
/// `flush`) plus auth state. Poll-based refresh (Realtime is a later upgrade).
@MainActor
final class SupabaseSync: ObservableObject {
    enum AuthProvider { case google, github }

    @Published private(set) var peers: [DeviceSnapshot] = []   // other devices only
    @Published private(set) var available = false              // project configured
    @Published private(set) var isSignedIn = false
    @Published private(set) var userEmail: String?
    @Published private(set) var lastError: String?

    private let client: SupabaseClient?
    private let table = "device_snapshots"
    private var authObserver: Task<Void, Never>?
    private var pollTimer: Timer?
    private var writeItem: DispatchWorkItem?
    private var lastSnapshot: DeviceSnapshot?
    private let writeDebounce: TimeInterval = 10
    private let pollInterval: TimeInterval = 45

    init() {
        if SupabaseConfig.isConfigured, let url = SupabaseConfig.url {
            client = SupabaseClient(supabaseURL: url, supabaseKey: SupabaseConfig.anonKey)
            available = true
        } else {
            client = nil
            available = false
        }
    }

    func start() {
        guard let client else { return }
        authObserver = Task { [weak self] in
            for await state in client.auth.authStateChanges {
                guard let self else { return }
                switch state.event {
                case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
                    self.onSignedIn(state.session)
                case .signedOut:
                    self.onSignedOut()
                default:
                    break
                }
            }
        }
    }

    // MARK: - Auth

    func signIn(_ provider: AuthProvider) {
        guard let client else { return }
        Task {
            do {
                switch provider {
                case .google:
                    try await client.auth.signInWithOAuth(
                        provider: .google, redirectTo: SupabaseConfig.redirectURL
                    ) { (session: ASWebAuthenticationSession) in
                        session.prefersEphemeralWebBrowserSession = false
                    }
                case .github:
                    try await client.auth.signInWithOAuth(
                        provider: .github, redirectTo: SupabaseConfig.redirectURL
                    ) { (session: ASWebAuthenticationSession) in
                        session.prefersEphemeralWebBrowserSession = false
                    }
                }
            } catch {
                self.lastError = error.localizedDescription
            }
        }
    }

    func signOut() {
        guard let client else { return }
        Task {
            try? await client.auth.signOut() // default .global scope (clean Keychain clear)
            self.onSignedOut()
        }
    }

    private func onSignedIn(_ session: Session?) {
        isSignedIn = true
        userEmail = session?.user.email
        lastError = nil
        startPolling()
        refreshPeers()
        if let snapshot = lastSnapshot { flush(snapshot) } // push our latest immediately
    }

    private func onSignedOut() {
        isSignedIn = false
        userEmail = nil
        peers = []
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Publish (own row)

    func publish(_ snapshot: DeviceSnapshot) {
        lastSnapshot = snapshot
        guard available, isSignedIn else { return }
        writeItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in await self?.upsert(snapshot) }
        }
        writeItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + writeDebounce, execute: item)
    }

    func flush(_ snapshot: DeviceSnapshot?) {
        guard let snapshot, available, isSignedIn else { return }
        writeItem?.cancel()
        Task { @MainActor in await upsert(snapshot) }
    }

    private func upsert(_ snapshot: DeviceSnapshot) async {
        guard let client, isSignedIn else { return }
        do {
            try await client.from(table)
                .upsert(DeviceSnapshotWrite(snapshot), onConflict: "user_id,device_id")
                .execute()
            await fetchPeers()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Read peers

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshPeers() }
        }
    }

    func refreshPeers() {
        Task { await fetchPeers() }
    }

    private func fetchPeers() async {
        guard let client, isSignedIn else { return }
        do {
            let rows: [DeviceSnapshotRow] = try await client.from(table)
                .select()
                .execute()
                .value
            let ownId = DeviceIdentity.id
            peers = rows.filter { $0.device_id != ownId }.map { $0.toSnapshot() }
        } catch {
            lastError = error.localizedDescription
        }
    }
}
