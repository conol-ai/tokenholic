import Foundation

/// Best-effort detection of the user's Claude plan from `~/.claude.json`, used
/// only to seed a sensible default monthly price. The user can always override.
enum PlanDetector {
    static func claudeRateLimitTier() -> String? {
        let url = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".claude.json")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = root["oauthAccount"] as? [String: Any],
              let tier = account["organizationRateLimitTier"] as? String
        else { return nil }
        return tier
    }

    /// Default monthly USD price inferred from the plan tier.
    static func claudeDefaultMonthlyPrice() -> Double {
        guard let tier = claudeRateLimitTier()?.lowercased() else { return 20 }
        if tier.contains("20x") { return 200 }   // Max 20×
        if tier.contains("5x") { return 100 }     // Max 5×
        return 20                                  // Pro
    }
}
