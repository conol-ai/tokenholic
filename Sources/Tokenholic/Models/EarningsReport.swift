import Foundation

/// One tool's monthly-cycle rollup, shown as a card.
struct ToolSummary: Identifiable {
    let id: String
    let tool: Tool
    let monthlyAPICostUSD: Double
    let subscriptionUSD: Double
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheWriteTokens: Int
    let recordCount: Int
    var netUSD: Double { monthlyAPICostUSD - subscriptionUSD }
}

/// API-equivalent value for a single day (all tools combined), for the sparkline.
struct DailyPoint: Identifiable {
    var id: Date { day }
    let day: Date
    let apiCostUSD: Double
}

/// Token usage + API value over a time window (blended across tools).
struct UsageWindow {
    let tokens: Int
    let apiCostUSD: Double
    let recordCount: Int
    var start: Date?
    var end: Date?

    static func from(_ records: [UsageRecord], start: Date? = nil, end: Date? = nil) -> UsageWindow {
        UsageWindow(
            tokens: records.reduce(0) { $0 + $1.totalTokens },
            apiCostUSD: records.reduce(0.0) { $0 + ($1.apiEquivalentCostUSD ?? 0) },
            recordCount: records.count,
            start: start,
            end: end
        )
    }
}

/// Aggregate earnings across all tools for the current billing cycle.
struct EarningsReport {
    var summaries: [ToolSummary] = []
    var blendedMonthlyAPICostUSD: Double = 0
    var blendedSubscriptionUSD: Double = 0
    var last5hCostUSD: Double = 0
    var dailyAPICost: [DailyPoint] = []
    var unpricedModels: [String] = []

    /// Active 5-hour session window; nil if no session is currently active.
    var session: UsageWindow?
    /// Rolling 7-day window.
    var week: UsageWindow?

    var blendedNetUSD: Double { blendedMonthlyAPICostUSD - blendedSubscriptionUSD }
}
