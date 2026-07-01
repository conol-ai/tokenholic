import Foundation

/// Per-token API prices for a model (USD).
struct ModelPrice: Sendable {
    let inputPerToken: Double
    let outputPerToken: Double
    let cacheReadPerToken: Double
    let cacheWrite5mPerToken: Double   // 5-minute ephemeral cache write
    let cacheWrite1hPerToken: Double   // 1-hour ephemeral cache write
}

/// Model-id normalization for price lookup.
///
/// The live LiteLLM table is keyed by exact model id (verified: every model in
/// real logs — including `claude-opus-4-8` and `claude-fable-5` — has an exact
/// entry). Family matching is only a last-resort fallback for unknown variants
/// so a brand-new dated model is never silently priced at $0.
enum ModelPricing {
    /// A current, definitely-present key to fall back to per model family.
    static func familyRepresentative(_ model: String) -> String? {
        let m = model.lowercased()
        if m.contains("opus") { return "claude-opus-4-8" }
        if m.contains("sonnet") { return "claude-sonnet-4-5" }
        if m.contains("haiku") { return "claude-haiku-4-5" }
        if m.contains("fable") { return "claude-fable-5" }
        if m.contains("gpt-5") || m.contains("gpt5") { return "gpt-5.5" }
        if m.contains("gemini") {
            if m.contains("flash-lite") { return "gemini-2.5-flash-lite" }
            if m.contains("flash") { return "gemini-2.5-flash" }
            return "gemini-2.5-pro"
        }
        return nil
    }
}

/// Offline fallback prices, baked into the binary so first-run / no-network
/// still produces correct numbers. Verified per-token values from LiteLLM
/// (2026-06-13). The live table overrides these whenever it loads.
enum EmbeddedPricing {
    private static func p(_ input: Double, _ output: Double, _ cacheRead: Double,
                          _ cacheWrite5m: Double, _ cacheWrite1h: Double) -> ModelPrice {
        ModelPrice(inputPerToken: input, outputPerToken: output,
                   cacheReadPerToken: cacheRead,
                   cacheWrite5mPerToken: cacheWrite5m, cacheWrite1hPerToken: cacheWrite1h)
    }

    static let table: [String: ModelPrice] = [
        // Opus 4.5+ : $5 / $25 (the post-4.5 price cut).
        "claude-opus-4-5": p(5e-6, 2.5e-5, 5e-7, 6.25e-6, 1e-5),
        "claude-opus-4-6": p(5e-6, 2.5e-5, 5e-7, 6.25e-6, 1e-5),
        "claude-opus-4-7": p(5e-6, 2.5e-5, 5e-7, 6.25e-6, 1e-5),
        "claude-opus-4-8": p(5e-6, 2.5e-5, 5e-7, 6.25e-6, 1e-5),
        // Sonnet 4.x : $3 / $15.
        "claude-sonnet-4-5": p(3e-6, 1.5e-5, 3e-7, 3.75e-6, 6e-6),
        // Haiku 4.5 : $1 / $5.
        "claude-haiku-4-5": p(1e-6, 5e-6, 1e-7, 1.25e-6, 2e-6),
        "claude-haiku-4-5-20251001": p(1e-6, 5e-6, 1e-7, 1.25e-6, 2e-6),
        // Fable 5 : $10 / $50.
        "claude-fable-5": p(1e-5, 5e-5, 1e-6, 1.25e-5, 2e-5),
        // OpenAI (for Codex, M4) — no cache-creation charge.
        "gpt-5": p(1.25e-6, 1e-5, 1.25e-7, 0, 0),
        "gpt-5.5": p(5e-6, 3e-5, 5e-7, 0, 0),
    ]
}
