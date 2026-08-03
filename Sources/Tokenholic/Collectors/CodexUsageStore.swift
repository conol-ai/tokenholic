import Foundation

/// Incremental, stateful reader for Codex CLI session logs.
///
/// The stateless `CodexCollector` re-reads and re-parses **every** rollout file
/// on every call, which on a real machine means hundreds of MB of JSON per
/// refresh — and `AppModel` refreshes on a 60s timer plus every FSEvent. This
/// store is the `ClaudeUsageStore` treatment for Codex: files whose size is
/// unchanged are skipped outright, and grown files are read from the last byte
/// offset (aligned to a newline boundary) to the end.
///
/// Incremental parsing is trickier here than for Claude because Codex logs
/// *cumulative* `total_token_usage` snapshots and we bill the delta between
/// consecutive snapshots. The running cumulative counters therefore have to
/// survive across scans, which is what `FileState` carries. Likewise `provider`
/// (from `session_meta`) and `model` (from `turn_context`) appear at the head of
/// a file but gate whether *any* record from it is emitted, so deltas parsed
/// before those are known are held in `pending` and materialized once they are.
///
/// An actor so overlapping refreshes can't corrupt the offset/state caches.
actor CodexUsageStore {
    private let directory: URL
    private var files: [String: FileState] = [:]
    /// Flattened view of `files`, rebuilt only when a file actually changes.
    private var cachedAll: [UsageRecord]?

    /// A token delta parsed before we knew the file's model, and so not yet
    /// expressible as a `UsageRecord`.
    private struct PendingDelta {
        let timestamp: Date
        let input: Int
        let output: Int
        let cacheRead: Int
    }

    private struct FileState {
        var size: UInt64 = 0
        var offset: UInt64 = 0
        var provider: String?
        var model: String?
        /// Running cumulative totals from the last snapshot seen in this file.
        var previousInput = 0
        var previousCached = 0
        var previousOutput = 0
        var pending: [PendingDelta] = []
        var records: [UsageRecord] = []
        /// Set once we know the file can never contribute (non-OpenAI provider
        /// or an internal support model). We keep tracking its size so we never
        /// read its bytes again.
        var rejected = false
    }

    init(directory: URL = CodexDataLocation.sessions) {
        self.directory = directory
    }

    /// Returns every known record, plus whether this scan ingested anything new
    /// — callers use that to skip re-deduping and re-pricing unchanged data.
    @discardableResult
    func scan() -> (records: [UsageRecord], changed: Bool) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path),
              let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey])
        else { return (allRecords(), false) }

        var changed = false
        var seen = Set<String>()
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let path = url.path
            seen.insert(path)
            let size = ((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize).map(UInt64.init) ?? 0

            var state = files[path] ?? FileState()
            if files[path] != nil {
                if size == state.size { continue }               // unchanged → skip
                if size < state.size {                            // shrunk/rotated → full re-read
                    state = FileState()
                }
            }
            if state.rejected {                                   // never re-read a rejected file
                state.size = size
                files[path] = state
                continue
            }
            consume(url: url, into: &state)
            state.size = size
            files[path] = state
            changed = true
        }

        // Drop state for files that no longer exist, so a long-running app
        // doesn't hold records for deleted sessions forever. Key-based, not
        // count-based: one delete plus one add leaves the counts equal but the
        // stale entry still present.
        if files.keys.contains(where: { !seen.contains($0) }) {
            files = files.filter { seen.contains($0.key) }
            changed = true
        }
        if changed { cachedAll = nil }
        return (allRecords(), changed)
    }

    private func allRecords() -> [UsageRecord] {
        if let cachedAll { return cachedAll }
        let all = files.values.flatMap { $0.records }
        cachedAll = all
        return all
    }

    /// Read complete lines from the state's offset to EOF and fold them into
    /// the file's running parse state. An incomplete trailing line is left
    /// unconsumed for the next scan.
    private func consume(url: URL, into state: inout FileState) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        do { try handle.seek(toOffset: state.offset) } catch { return }
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return }
        guard let lastNewline = data.lastIndex(of: 0x0A) else { return }

        let consumable = data[...lastNewline]
        state.offset += UInt64(consumable.count)

        // One decoder for the whole blob rather than one per line.
        let decoder = JSONDecoder()
        for lineData in consumable.split(separator: 0x0A, omittingEmptySubsequences: true) {
            guard let line = try? decoder.decode(CodexLine.self, from: Data(lineData)) else { continue }
            switch line.type {
            case "session_meta":
                if state.provider == nil { state.provider = line.payload?.model_provider }
            case "turn_context":
                if state.model == nil, let m = line.payload?.model { state.model = m }
            case "event_msg":
                guard line.payload?.type == "token_count",
                      let usage = line.payload?.info?.total_token_usage,  // guards info == null
                      let ts = ISO8601.parse(line.timestamp) else { break }
                appendDelta(usage: usage, timestamp: ts, into: &state)
            default:
                break
            }
        }

        flushPending(url: url, into: &state)
    }

    /// Bill the delta against the previous cumulative snapshot in this file.
    private func appendDelta(usage: CodexUsage, timestamp: Date, into state: inout FileState) {
        let currentInput = usage.input_tokens ?? 0
        let currentCached = usage.cached_input_tokens ?? 0
        let currentOutput = usage.output_tokens ?? 0

        let deltaInput = max(0, currentInput - state.previousInput)
        let deltaCached = max(0, currentCached - state.previousCached)
        let deltaOutput = max(0, currentOutput - state.previousOutput)
        state.previousInput = currentInput
        state.previousCached = currentCached
        state.previousOutput = currentOutput

        if deltaInput == 0, deltaOutput == 0, deltaCached == 0 { return }
        state.pending.append(PendingDelta(
            timestamp: timestamp,
            // cached ⊆ input → bill non-cached input at input rate, cached at
            // the cache-read rate. reasoning ⊆ output → already in output.
            input: max(0, deltaInput - deltaCached),
            output: deltaOutput,
            cacheRead: deltaCached
        ))
    }

    /// Materialize buffered deltas once the file's provider + model are known.
    /// Only user-facing OpenAI sessions are API-priceable; in particular
    /// auto-review is an internal permission check, not a coding session.
    private func flushPending(url: URL, into state: inout FileState) {
        guard let provider = state.provider, let model = state.model else { return }
        guard provider == "openai", !CodexParser.internalModels.contains(model.lowercased()) else {
            state.rejected = true
            state.pending.removeAll()
            state.records.removeAll()
            return
        }
        guard !state.pending.isEmpty else { return }

        let sessionId = url.deletingPathExtension().lastPathComponent
        state.records.append(contentsOf: state.pending.map { delta in
            UsageRecord(
                tool: .codex,
                timestamp: delta.timestamp,
                model: model,
                inputTokens: delta.input,
                outputTokens: delta.output,
                cacheReadTokens: delta.cacheRead,
                cacheCreate5mTokens: 0,
                cacheCreate1hTokens: 0,
                dedupKey: nil,                 // session logs are unique; never collapse
                isSidechain: false,
                sessionId: sessionId,
                sourcePath: url.path
            )
        })
        state.pending.removeAll()
    }
}
