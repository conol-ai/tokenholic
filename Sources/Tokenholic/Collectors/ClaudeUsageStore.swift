import Foundation

/// Incremental, stateful reader for Claude Code transcripts.
///
/// Transcripts are append-only JSONL, so each `scan()` only reads what's new:
/// files whose size is unchanged are skipped, and grown files are read from the
/// last byte offset (aligned to a newline boundary) to the end. An actor so
/// overlapping refreshes can't corrupt the offset/record caches.
actor ClaudeUsageStore {
    private let directory: URL
    private var fileSizes: [String: UInt64] = [:]
    private var fileOffsets: [String: UInt64] = [:]
    private var recordsByFile: [String: [UsageRecord]] = [:]
    /// Flattened view of `recordsByFile`, rebuilt only when a file actually
    /// changes. Without this, every scan re-flattened the entire history (tens
    /// of thousands of records) just to hand back an unchanged array.
    private var cachedAll: [UsageRecord]?

    init(directory: URL = ClaudeDataLocation.projects) {
        self.directory = directory
    }

    /// Returns every known record, plus whether this scan ingested anything new
    /// — callers use that to skip re-deduping and re-pricing unchanged data.
    @discardableResult
    func scan() -> (records: [UsageRecord], changed: Bool) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return (allRecords(), false)
        }

        var changed = false
        var seen = Set<String>()
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let path = url.path
            seen.insert(path)
            let size = ((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize).map(UInt64.init) ?? 0

            if let previous = fileSizes[path] {
                if size == previous { continue }                 // unchanged → skip
                if size > previous {                              // appended → read the tail
                    let (records, offset) = readTail(url: url, from: fileOffsets[path] ?? 0)
                    recordsByFile[path, default: []].append(contentsOf: records)
                    fileOffsets[path] = offset
                } else {                                          // shrunk/rotated → full re-read
                    let (records, offset) = readTail(url: url, from: 0)
                    recordsByFile[path] = records
                    fileOffsets[path] = offset
                }
            } else {                                              // new file → full read
                let (records, offset) = readTail(url: url, from: 0)
                recordsByFile[path] = records
                fileOffsets[path] = offset
            }
            fileSizes[path] = size
            changed = true
        }

        // Drop state for transcripts that no longer exist, so a long-running app
        // doesn't hold records (and offsets) for deleted sessions forever.
        // Key-based, not count-based: one delete plus one add leaves the counts
        // equal but the stale entry still present.
        if fileSizes.keys.contains(where: { !seen.contains($0) }) {
            fileSizes = fileSizes.filter { seen.contains($0.key) }
            fileOffsets = fileOffsets.filter { seen.contains($0.key) }
            recordsByFile = recordsByFile.filter { seen.contains($0.key) }
            changed = true
        }
        if changed { cachedAll = nil }
        return (allRecords(), changed)
    }

    private func allRecords() -> [UsageRecord] {
        if let cachedAll { return cachedAll }
        let all = recordsByFile.values.flatMap { $0 }
        cachedAll = all
        return all
    }

    /// Read complete lines from `offset` to EOF; returns the parsed records and
    /// the new offset (just past the last newline). An incomplete trailing line
    /// is left unconsumed for the next scan.
    private func readTail(url: URL, from offset: UInt64) -> ([UsageRecord], UInt64) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return ([], offset) }
        defer { try? handle.close() }
        do { try handle.seek(toOffset: offset) } catch { return ([], offset) }
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return ([], offset) }
        guard let lastNewline = data.lastIndex(of: 0x0A) else { return ([], offset) }

        let consumable = data[...lastNewline]
        let newOffset = offset + UInt64(consumable.count)
        let records = ClaudeParser.parse(
            data: Data(consumable),
            sourcePath: url.path,
            sessionId: url.deletingPathExtension().lastPathComponent
        )
        return (records, newOffset)
    }
}
