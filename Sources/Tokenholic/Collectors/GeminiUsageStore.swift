import Foundation

/// Incremental, stateful reader for the Gemini CLI telemetry log.
///
/// The stateless `GeminiCliCollector` reads and re-parses the whole log on every
/// call. The log is append-only, so this store keeps a byte offset and reads
/// only what is new — and skips the read entirely when the file's size is
/// unchanged, which is the common case on a 60s refresh tick.
///
/// The offset only ever advances to the end of the last *complete* top-level
/// JSON object, so a half-written record at EOF is re-read on the next scan
/// rather than being lost or parsed as garbage.
actor GeminiUsageStore {
    private let path: String
    private var size: UInt64 = 0
    private var offset: UInt64 = 0
    private var records: [UsageRecord] = []
    private var everScanned = false

    init(path: String = GeminiDataLocation.telemetryLog) {
        self.path = path
    }

    /// Returns every known record, plus whether this scan ingested anything new
    /// — callers use that to skip re-deduping and re-pricing unchanged data.
    @discardableResult
    func scan() -> (records: [UsageRecord], changed: Bool) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else {
            // Log removed (or telemetry never enabled) → drop any stale records.
            let had = !records.isEmpty
            records.removeAll()
            size = 0
            offset = 0
            return ([], had)
        }

        let current = ((try? fm.attributesOfItem(atPath: path)[.size]) as? NSNumber)
            .map { $0.uint64Value } ?? 0

        if everScanned, current == size { return (records, false) }  // unchanged → skip
        if current < size {                                          // truncated/rotated → start over
            offset = 0
            records.removeAll()
        }
        everScanned = true
        size = current

        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else {
            return (records, false)
        }
        defer { try? handle.close() }
        do { try handle.seek(toOffset: offset) } catch { return (records, false) }
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return (records, false) }

        let (new, consumed) = GeminiCliCollector.parse(data: data, sourcePath: path)
        records.append(contentsOf: new)
        offset += UInt64(consumed)
        return (records, true)
    }
}
