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

/// Aggregate earnings across all tools for the current billing cycle.
struct EarningsReport {
    var summaries: [ToolSummary] = []
    var blendedMonthlyAPICostUSD: Double = 0
    var blendedSubscriptionUSD: Double = 0
    var last5hCostUSD: Double = 0
    var dailyAPICost: [DailyPoint] = []
    var unpricedModels: [String] = []

    var blendedNetUSD: Double { blendedMonthlyAPICostUSD - blendedSubscriptionUSD }
}
