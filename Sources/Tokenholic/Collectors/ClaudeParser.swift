import Foundation

/// Parses Claude Code transcript bytes (newline-delimited JSON) into records.
/// Shared by the full-scan `ClaudeCollector` and the incremental `ClaudeUsageStore`.
enum ClaudeParser {
    /// Parse a blob of one-or-more transcript lines.
    static func parse(data: Data, sourcePath: String, sessionId: String) -> [UsageRecord] {
        var out: [UsageRecord] = []
        for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            if let record = parseLine(Data(line), sourcePath: sourcePath, sessionId: sessionId) {
                out.append(record)
            }
        }
        return out
    }

    /// Read and parse an entire transcript file.
    static func parseFile(at url: URL) -> [UsageRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return parse(data: data,
                     sourcePath: url.path,
                     sessionId: url.deletingPathExtension().lastPathComponent)
    }

    private static func parseLine(_ lineData: Data, sourcePath: String, sessionId: String) -> UsageRecord? {
        guard !lineData.isEmpty,
              let raw = try? JSONDecoder().decode(RawLine.self, from: lineData),
              raw.type == "assistant",
              let message = raw.message,
              let usage = message.usage,
              let model = message.model,
              model != "<synthetic>",                 // verified synthetic marker
              let timestamp = ISO8601.parse(raw.timestamp)
        else { return nil }

        // Prefer the explicit 5m/1h cache-write breakdown; fall back to the flat field.
        let cache5m: Int
        let cache1h: Int
        if let breakdown = usage.cache_creation {
            cache5m = breakdown.ephemeral_5m_input_tokens ?? 0
            cache1h = breakdown.ephemeral_1h_input_tokens ?? 0
        } else {
            cache5m = usage.cache_creation_input_tokens ?? 0
            cache1h = 0
        }

        let dedupKey: String?
        if let messageId = message.id, let requestId = raw.requestId {
            dedupKey = "\(messageId)|\(requestId)"
        } else {
            dedupKey = nil
        }

        return UsageRecord(
            tool: .claudeCode,
            timestamp: timestamp,
            model: model,
            inputTokens: usage.input_tokens ?? 0,
            outputTokens: usage.output_tokens ?? 0,
            cacheReadTokens: usage.cache_read_input_tokens ?? 0,
            cacheCreate5mTokens: cache5m,
            cacheCreate1hTokens: cache1h,
            dedupKey: dedupKey,
            isSidechain: raw.isSidechain ?? false,
            sessionId: raw.sessionId ?? sessionId,
            sourcePath: sourcePath
        )
    }
}

// MARK: - Raw JSON shapes (only the fields we need)

private struct RawLine: Decodable {
    let type: String?
    let timestamp: String?
    let requestId: String?
    let isSidechain: Bool?
    let sessionId: String?
    let message: RawMessage?
}

private struct RawMessage: Decodable {
    let id: String?
    let model: String?
    let usage: RawUsage?
}

private struct RawUsage: Decodable {
    let input_tokens: Int?
    let output_tokens: Int?
    let cache_read_input_tokens: Int?
    let cache_creation_input_tokens: Int?
    let cache_creation: RawCacheCreation?
}

private struct RawCacheCreation: Decodable {
    let ephemeral_5m_input_tokens: Int?
    let ephemeral_1h_input_tokens: Int?
}

// MARK: - Timestamp parsing

enum ISO8601 {
    private static let withFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ string: String?) -> Date? {
        guard let s = string else { return nil }
        return withFractional.date(from: s) ?? plain.date(from: s)
    }
}
