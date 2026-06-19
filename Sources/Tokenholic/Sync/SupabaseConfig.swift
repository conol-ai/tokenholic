import Foundation

/// Supabase project configuration.
///
/// The publishable key is SAFE to embed — Row-Level Security guarantees a
/// request can only ever touch the signed-in user's own rows, and an
/// unauthenticated request matches nothing. NEVER put the `secret` key
/// (`sb_secret_…`) here (it bypasses RLS).
///
/// `publishableKey` is the modern replacement for the legacy `anon` key; both
/// fill the same client-side, RLS-scoped role. Find these in your Supabase
/// project → Settings → Data API (URL) and Settings → API Keys (publishable
/// key). Until both are set to real values, sync is disabled and Tokenholic
/// runs local-only. See SUPABASE_SETUP.md.
enum SupabaseConfig {
    static let projectURL = "https://czecjlkajmjnvabblpxu.supabase.co"
    static let publishableKey = "sb_publishable_dnu3WIDOL3dlVkj0UN1vNw_InQV5klK"

    /// OAuth redirect back into the app. Must match exactly (lowercase):
    /// - App/Info.plist → CFBundleURLTypes
    /// - Supabase → Authentication → URL Configuration → Redirect URLs
    static let redirectURL = URL(string: "ai.conol.tokenholic://auth-callback")!

    static var url: URL? { URL(string: projectURL) }

    static var isConfigured: Bool {
        url != nil
            && !projectURL.contains("YOUR_PROJECT_REF")
            && !publishableKey.contains("YOUR_SUPABASE")
    }
}
