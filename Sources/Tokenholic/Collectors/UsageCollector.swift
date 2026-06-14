import Foundation

/// A source of token-usage records for one tool. Implementations read local
/// logs (or, for Cursor later, an HTTP API) and return raw, un-deduplicated
/// records. Normalization/dedup happens downstream in `Normalizer`.
protocol UsageCollector: Sendable {
    var tool: Tool { get }
    func collect() throws -> [UsageRecord]
}
