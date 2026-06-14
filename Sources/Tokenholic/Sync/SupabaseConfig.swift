import Foundation

/// Supabase project configuration.
///
/// The anon (public) key is SAFE to embed — Row-Level Security guarantees a
/// request can only ever touch the signed-in user's own rows, and an
/// unauthenticated request matches nothing. NEVER put the `service_role` key
/// here (it bypasses RLS).
///
/// Fill these in from your Supabase project → Settings → API. Until both are set
/// to real values, sync is disabled and Tokenholic runs local-only. See
/// SUPABASE_SETUP.md.
enum SupabaseConfig {
    static let projectURL = "https://YOUR_PROJECT_REF.supabase.co"
    static let anonKey = "YOUR_SUPABASE_ANON_KEY"

    /// OAuth redirect back into the app. Must match exactly (lowercase):
    /// - App/Info.plist → CFBundleURLTypes
    /// - Supabase → Authentication → URL Configuration → Redirect URLs
    static let redirectURL = URL(string: "ai.conol.tokenholic://auth-callback")!

    static var url: URL? { URL(string: projectURL) }

    static var isConfigured: Bool {
        url != nil
            && !projectURL.contains("YOUR_PROJECT_REF")
            && !anonKey.contains("YOUR_SUPABASE")
    }
}
