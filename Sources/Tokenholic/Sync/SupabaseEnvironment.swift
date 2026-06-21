import Foundation
import Supabase

/// Single source of the app's `SupabaseClient`.
///
/// Both `SupabaseSync` (cross-device totals) and `SocialService` (friends +
/// leaderboard) take THIS instance so they share one auth session — one
/// Keychain store, one token refresh, one `authStateChanges` stream. Building
/// two `SupabaseClient`s would create two independent auth stores and let
/// sign-in state diverge between the two features.
///
/// `available` mirrors `SupabaseSync`'s gate: until `SupabaseConfig` holds a
/// real project URL + publishable key, there is no client and both services run
/// in a disabled, local-only state.
@MainActor
final class SupabaseEnvironment {
    let client: SupabaseClient?
    var available: Bool { client != nil }

    init() {
        if SupabaseConfig.isConfigured, let url = SupabaseConfig.url {
            client = SupabaseClient(supabaseURL: url, supabaseKey: SupabaseConfig.publishableKey)
        } else {
            client = nil
        }
    }
}
