import Foundation

/// Computes the API-equivalent USD cost of a `UsageRecord`.
///
/// Mirrors ccusage's `calculate_cost_from_tokens`: each token bucket is priced
/// independently and summed, with the 5m/1h cache-write split priced at its own
/// rate. Prices come from the injected table (live LiteLLM + embedded fallback).
struct PricingEngine: Sendable {
    let table: [String: ModelPrice]

    /// Resolve a model id to a price: exact key → lowercased → last path
    /// component → family representative. nil ⇒ genuinely unknown.
    func price(for model: String) -> ModelPrice? {
        if let p = table[model] { return p }
        let lower = model.lowercased()
        if let p = table[lower] { return p }
        if let last = lower.split(separator: "/").last, let p = table[String(last)] { return p }
        if let rep = ModelPricing.familyRepresentative(lower), let p = table[rep] { return p }
        return nil
    }

    func cost(for record: UsageRecord) -> Double? {
        guard let p = price(for: record.model) else { return nil }
        return Double(record.inputTokens) * p.inputPerToken
            + Double(record.outputTokens) * p.outputPerToken
            + Double(record.cacheReadTokens) * p.cacheReadPerToken
            + Double(record.cacheCreate5mTokens) * p.cacheWrite5mPerToken
            + Double(record.cacheCreate1hTokens) * p.cacheWrite1hPerToken
    }
}
