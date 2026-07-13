import Foundation

/// Canonical Codex CLI session-log location.
enum CodexDataLocation {
    static var sessions: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true)
    }
}

/// Reads OpenAI Codex CLI usage from `~/.codex/sessions/**/rollout-*.jsonl`.
///
/// Codex logs *cumulative* `total_token_usage` snapshots per turn. We bucket by
/// the delta between consecutive snapshots (attributed to the event timestamp)
/// — never `last_token_usage`, which is cumulative-within-turn and overcounts.
struct CodexCollector: UsageCollector {
    let tool: Tool = .codex
    var sessionsDirectory: URL = CodexDataLocation.sessions

    func collect() throws -> [UsageRecord] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sessionsDirectory.path),
              let enumerator = fm.enumerator(at: sessionsDirectory, includingPropertiesForKeys: nil)
        else { return [] }

        var records: [UsageRecord] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            records.append(contentsOf: CodexParser.parseFile(at: url))
        }
        return records
    }
}

enum CodexParser {
    /// Hidden Codex support models run as separate sessions but are not part of
    /// the user's coding workload and have no public API-equivalent price.
    private static let internalModels: Set<String> = ["codex-auto-review"]

    static func parseFile(at url: URL) -> [UsageRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let sessionId = url.deletingPathExtension().lastPathComponent

        var provider: String?
        var model: String?
        var snapshots: [(timestamp: Date, usage: CodexUsage)] = []

        for lineData in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            guard let line = try? JSONDecoder().decode(CodexLine.self, from: Data(lineData)) else { continue }
            switch line.type {
            case "session_meta":
                if provider == nil { provider = line.payload?.model_provider }
            case "turn_context":
                if model == nil, let m = line.payload?.model { model = m }
            case "event_msg":
                if line.payload?.type == "token_count",
                   let usage = line.payload?.info?.total_token_usage,   // guards info == null
                   let ts = ISO8601.parse(line.timestamp) {
                    snapshots.append((ts, usage))
                }
            default:
                break
            }
        }

        // Only user-facing OpenAI sessions are API-priceable. In particular,
        // auto-review is an internal permission check, not a coding session.
        guard provider == "openai", let model,
              !internalModels.contains(model.lowercased()) else { return [] }

        var previousInput = 0, previousCached = 0, previousOutput = 0
        var records: [UsageRecord] = []
        for (timestamp, usage) in snapshots {
            let currentInput = usage.input_tokens ?? 0
            let currentCached = usage.cached_input_tokens ?? 0
            let currentOutput = usage.output_tokens ?? 0

            let deltaInput = max(0, currentInput - previousInput)
            let deltaCached = max(0, currentCached - previousCached)
            let deltaOutput = max(0, currentOutput - previousOutput)
            previousInput = currentInput
            previousCached = currentCached
            previousOutput = currentOutput

            if deltaInput == 0, deltaOutput == 0, deltaCached == 0 { continue }

            // cached ⊆ input → bill non-cached input at input rate, cached at
            // the cache-read rate. reasoning ⊆ output → already in output.
            records.append(UsageRecord(
                tool: .codex,
                timestamp: timestamp,
                model: model,
                inputTokens: max(0, deltaInput - deltaCached),
                outputTokens: deltaOutput,
                cacheReadTokens: deltaCached,
                cacheCreate5mTokens: 0,
                cacheCreate1hTokens: 0,
                dedupKey: nil,                 // session logs are unique; never collapse
                isSidechain: false,
                sessionId: sessionId,
                sourcePath: url.path
            ))
        }
        return records
    }
}

// MARK: - Raw JSON shapes

private struct CodexLine: Decodable {
    let type: String?
    let timestamp: String?
    let payload: CodexPayload?
}

private struct CodexPayload: Decodable {
    let type: String?            // "token_count" (within event_msg)
    let model: String?           // turn_context
    let model_provider: String?  // session_meta
    let info: CodexInfo?         // token_count
}

private struct CodexInfo: Decodable {
    let total_token_usage: CodexUsage?
}

struct CodexUsage: Decodable {
    let input_tokens: Int?
    let cached_input_tokens: Int?
    let output_tokens: Int?
    let reasoning_output_tokens: Int?
    let total_tokens: Int?
}
