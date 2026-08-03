import Foundation

/// Where Gemini CLI writes its local telemetry when the user opts in with
/// `telemetry: { enabled: true, target: "local", outfile: "~/.gemini/telemetry.log" }`
/// in `~/.gemini/settings.json`. Unlike Claude Code / Codex (always-on session
/// logs), Gemini CLI telemetry is **off by default** — this collector is inert
/// until the user enables it and points the outfile here.
enum GeminiDataLocation {
    static var telemetryLog: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".gemini/telemetry.log")
    }
}

/// Reads Gemini CLI's local OpenTelemetry log file and turns each
/// `gemini_cli.api_response` event into a `UsageRecord`.
///
/// The file is a stream of OTEL log records (one JSON object each, pretty-printed
/// and concatenated) written by the SDK's file exporter. Each api_response record
/// carries flat token attributes emitted by the CLI's `toLogRecord()`:
///   event.name = "gemini_cli.api_response", model, input_token_count,
///   output_token_count, cached_content_token_count, thoughts_token_count,
///   total_token_count, event.timestamp, session.id
/// (schema verified against gemini-cli source + a captured telemetry.log).
struct GeminiCliCollector: UsageCollector {
    let tool: Tool = .geminiCli
    var logPath: String = GeminiDataLocation.telemetryLog

    func collect() throws -> [UsageRecord] {
        guard let data = FileManager.default.contents(atPath: logPath) else { return [] }
        return Self.parse(data: data, sourcePath: logPath).records
    }

    // MARK: - Parsing (pure; unit-testable without the filesystem)

    private static let API_RESPONSE = "gemini_cli.api_response"

    static func parse(_ text: String, sourcePath: String) -> [UsageRecord] {
        parse(data: Data(text.utf8), sourcePath: sourcePath).records
    }

    /// Byte-level parse of a blob of concatenated JSON objects. Returns the
    /// records plus how many bytes were consumed — an incomplete trailing
    /// object is left unconsumed so an incremental reader can retry it once
    /// more of the file has been written.
    static func parse(data: Data, sourcePath: String) -> (records: [UsageRecord], consumed: Int) {
        var out: [UsageRecord] = []
        let (ranges, consumed) = topLevelJSONRanges(in: data)
        // One decoder for the whole blob rather than one per object.
        let decoder = JSONDecoder()
        for range in ranges {
            guard let rec = try? decoder.decode(LogRecord.self, from: data[range]),
                  let a = rec.attributes,
                  a.eventName == API_RESPONSE,
                  let model = a.model, !model.isEmpty else { continue }

            let input = max(0, a.inputTokenCount ?? 0)
            let cached = max(0, a.cachedContentTokenCount ?? 0)
            let output = max(0, a.outputTokenCount ?? 0)
            let thoughts = max(0, a.thoughtsTokenCount ?? 0)
            // Gemini bills the cached slice at a reduced rate, so price it as
            // cache-read and keep only the fresh (non-cached) prompt as input.
            // Thinking tokens are billed as output.
            let freshInput = max(0, input - cached)
            let outTokens = output + thoughts
            if freshInput == 0 && cached == 0 && outTokens == 0 { continue }

            let ts = a.eventTimestamp.flatMap(parseTimestamp) ?? Date()
            let session = a.sessionId ?? ""
            out.append(UsageRecord(
                id: UUID(),
                tool: .geminiCli,
                timestamp: ts,
                model: model,
                inputTokens: freshInput,
                outputTokens: outTokens,
                cacheReadTokens: cached,
                cacheCreate5mTokens: 0,   // Gemini has no separate cache-write billing
                cacheCreate1hTokens: 0,
                // Stable per-call key so re-reading the append-only log across
                // rescans collapses to one record (ms-precision timestamp + session).
                dedupKey: "gemini|\(session)|\(a.eventTimestamp ?? "")|\(a.totalTokenCount ?? outTokens)",
                isSidechain: false,
                sessionId: session,
                sourcePath: sourcePath
            ))
        }
        return (out, consumed)
    }

    /// Split a stream of concatenated JSON objects into byte ranges of complete
    /// top-level objects by tracking brace depth (string- and escape-aware),
    /// plus the number of bytes consumed (i.e. the end of the last complete
    /// object). Scanning raw UTF-8 bytes avoids the cost of walking a Swift
    /// `String` by grapheme-aware `String.Index`, which dominated this parse.
    private static func topLevelJSONRanges(in data: Data) -> (ranges: [Range<Data.Index>], consumed: Int) {
        var ranges: [Range<Data.Index>] = []
        var depth = 0
        var inString = false
        var escaped = false
        var start: Data.Index?
        var consumed = 0

        let quote = UInt8(ascii: "\""), backslash = UInt8(ascii: "\\")
        let open = UInt8(ascii: "{"), close = UInt8(ascii: "}")

        for i in data.indices {
            let byte = data[i]
            if inString {
                if escaped { escaped = false }
                else if byte == backslash { escaped = true }
                else if byte == quote { inString = false }
            } else {
                switch byte {
                case quote: inString = true
                case open:
                    if depth == 0 { start = i }
                    depth += 1
                case close:
                    // Guard against stray '}' outside any object.
                    guard depth > 0 else { break }
                    depth -= 1
                    if depth == 0, let s = start {
                        let end = data.index(after: i)
                        ranges.append(s..<end)
                        consumed = data.distance(from: data.startIndex, to: end)
                        start = nil
                    }
                default: break
                }
            }
        }
        return (ranges, consumed)
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain = ISO8601DateFormatter()

    private static func parseTimestamp(_ s: String) -> Date? {
        isoFractional.date(from: s) ?? isoPlain.date(from: s)
    }

    // Only the fields we need; unknown keys are ignored.
    private struct LogRecord: Decodable {
        let attributes: Attrs?
        struct Attrs: Decodable {
            let eventName: String?
            let eventTimestamp: String?
            let sessionId: String?
            let model: String?
            let inputTokenCount: Int?
            let outputTokenCount: Int?
            let cachedContentTokenCount: Int?
            let thoughtsTokenCount: Int?
            let totalTokenCount: Int?
            enum CodingKeys: String, CodingKey {
                case eventName = "event.name"
                case eventTimestamp = "event.timestamp"
                case sessionId = "session.id"
                case model
                case inputTokenCount = "input_token_count"
                case outputTokenCount = "output_token_count"
                case cachedContentTokenCount = "cached_content_token_count"
                case thoughtsTokenCount = "thoughts_token_count"
                case totalTokenCount = "total_token_count"
            }
        }
    }
}
