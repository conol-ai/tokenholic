import Foundation

/// One normalized unit of token usage, tool-agnostic.
///
/// Every collector maps its tool-native log format into this shape; the
/// Normalizer dedups them and the PricingEngine fills in `apiEquivalentCostUSD`.
struct UsageRecord: Identifiable, Sendable {
    let id: UUID
    let tool: Tool
    let timestamp: Date          // UTC instant the usage was recorded
    let model: String            // raw model id, e.g. "claude-opus-4-8"
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheCreate5mTokens: Int // 5-minute ephemeral cache writes
    let cacheCreate1hTokens: Int // 1-hour ephemeral cache writes

    /// Compound identity for dedup ("messageId|requestId" for Claude). When
    /// nil, the record is treated as always-unique (never collapsed).
    let dedupKey: String?
    let isSidechain: Bool
    let sessionId: String
    let sourcePath: String

    /// Filled by `PricingEngine`. nil ⇒ no pricing data for this model.
    var apiEquivalentCostUSD: Double?

    var totalTokens: Int {
        inputTokens + outputTokens + cacheReadTokens + cacheCreate5mTokens + cacheCreate1hTokens
    }

    init(
        id: UUID = UUID(),
        tool: Tool,
        timestamp: Date,
        model: String,
        inputTokens: Int,
        outputTokens: Int,
        cacheReadTokens: Int,
        cacheCreate5mTokens: Int,
        cacheCreate1hTokens: Int,
        dedupKey: String?,
        isSidechain: Bool,
        sessionId: String,
        sourcePath: String,
        apiEquivalentCostUSD: Double? = nil
    ) {
        self.id = id
        self.tool = tool
        self.timestamp = timestamp
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheCreate5mTokens = cacheCreate5mTokens
        self.cacheCreate1hTokens = cacheCreate1hTokens
        self.dedupKey = dedupKey
        self.isSidechain = isSidechain
        self.sessionId = sessionId
        self.sourcePath = sourcePath
        self.apiEquivalentCostUSD = apiEquivalentCostUSD
    }
}
