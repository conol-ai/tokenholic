import Foundation

// ============================================================================
// Wire types for the social backend (supabase/social.sql).
//
// Read rows use snake_case property names that match the column / RPC output
// names exactly (same convention as DeviceSnapshotRow) so no CodingKeys are
// needed. Write/param payloads omit server-owned columns (user_id, updated_at)
// — user_id is defaulted from auth.uid() and freshness is trigger-stamped, so a
// hostile client holding the publishable key + a session cannot forge ownership
// or another user's numbers. Cross-user reads only ever arrive via the
// friendship-gated SECURITY DEFINER RPCs, never raw cross-user SELECTs.
// ============================================================================

/// A transient user-facing message for the social UI. `seq` makes two identical
/// messages distinct so repeating an action always re-triggers the toast (an
/// `onChange` observer only fires when the value actually changes).
struct SocialToast: Equatable {
    let text: String
    let isError: Bool
    let seq: Int
}

// MARK: - Read rows

/// The caller's own profile (RLS: select own). `share_daily_total` backs the
/// visible "Share my daily total with friends" toggle.
struct ProfileRow: Decodable {
    let user_id: String
    let handle: String?
    let display_name: String?
    let avatar_url: String?
    let share_daily_total: Bool
}

/// One accepted friend, from the `list_friends` RPC (joins profiles server-side
/// so the client never reads another user's profile row directly). `sharing`
/// reflects whether they currently appear on your board.
struct FriendRow: Decodable, Identifiable {
    let user_id: String
    let handle: String?
    let display_name: String?
    let avatar_url: String?
    let sharing: Bool
    let befriended_at: Date
    var id: String { user_id }
}

/// A pending friend request (either direction), from the `list_requests` RPC.
struct RequestRow: Decodable, Identifiable {
    let request_id: String
    let other_user_id: String
    let handle: String?
    let display_name: String?
    let direction: String          // "incoming" | "outgoing"
    let created_at: Date
    var id: String { request_id }
    var isIncoming: Bool { direction == "incoming" }
}

/// One leaderboard entry for a local day, from the `leaderboard_for_day` RPC.
/// `api_value_usd` is GROSS Daily API value — never net, never plan price.
struct LeaderboardRow: Decodable, Identifiable {
    let user_id: String
    let handle: String?
    let display_name: String?
    let avatar_url: String?
    let api_value_usd: Double
    let tokens: Int
    let is_self: Bool
    var id: String { user_id }
}

/// An invite the caller owns (RLS: select own). Surfaced as a shareable link.
struct InviteRow: Decodable, Identifiable {
    let code: String
    let active: Bool?
    let max_uses: Int?
    let use_count: Int?
    let expires_at: Date?
    let created_at: Date?
    var id: String { code }
    var url: URL? { InviteURL.make(code: code) }
    var isLive: Bool {
        (active ?? false) && (expires_at.map { $0 > Date() } ?? true) && (use_count ?? 0) < (max_uses ?? 1)
    }
}

/// A handle-search hit from `lookup_profile_by_handle` (minimal projection: just
/// enough to send a request, no display_name/avatar to a non-friend).
struct HandleHit: Decodable {
    let user_id: String
    let handle: String
}

/// Result of redeeming an invite. Empty set ⇒ the redemption routed a pending
/// request instead of an instant friendship (revoked/declined pair).
struct RedeemResult: Decodable {
    let friend_user_id: String
    let friend_handle: String?
    let friend_display_name: String?
}

// MARK: - Write payloads / RPC params  (keys = SQL arg names, p_-prefixed)

/// One device's gross Daily API value for a local day. ONE row per
/// (user_id, device_id, day); user_id is defaulted server-side from auth.uid().
struct DailyValueWrite: Encodable {
    let device_id: String
    let day: String                // local "yyyy-MM-dd" (client's calendar)
    let api_usd: Double
    let tokens: Int
}

struct ClaimHandleParams: Encodable {
    let p_handle: String
    let p_display_name: String?
    let p_avatar_url: String?
}
struct SharePrefParams: Encodable { let p_share: Bool }
struct HandleParam: Encodable { let p_handle: String }
struct AddresseeParam: Encodable { let p_addressee: String }
struct RequestIdParam: Encodable { let p_request_id: String }
struct OtherParam: Encodable { let p_other: String }
struct CodeParam: Encodable { let p_code: String }
struct DayParam: Encodable { let p_day: String }
struct UpsertDailyParams: Encodable {
    let p_device_id: String
    let p_day: String
    let p_api_value: Double
    let p_tokens: Int
}
