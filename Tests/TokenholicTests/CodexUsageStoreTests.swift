import Foundation
import XCTest
@testable import Tokenholic

/// The incremental store has to reproduce `CodexCollector`'s output exactly
/// while reading each byte only once. The delicate parts are that Codex logs
/// *cumulative* token snapshots (so the running totals must survive across
/// scans) and that `session_meta` / `turn_context` sit at the head of a file but
/// gate whether any record from it is emitted at all.
final class CodexUsageStoreTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Helpers

    private static let head = """
    {"timestamp":"2026-07-13T10:00:00Z","type":"session_meta","payload":{"model_provider":"openai"}}
    {"timestamp":"2026-07-13T10:00:01Z","type":"turn_context","payload":{"model":"gpt-5.5"}}

    """

    private static func snapshot(_ second: Int, input: Int, cached: Int, output: Int) -> String {
        """
        {"timestamp":"2026-07-13T10:00:\(String(format: "%02d", second))Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\(input),"cached_input_tokens":\(cached),"output_tokens":\(output)}}}}

        """
    }

    private func write(_ text: String, to name: String) throws {
        try text.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    private func append(_ text: String, to name: String) throws {
        let url = dir.appendingPathComponent(name)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    private func fields(_ records: [UsageRecord]) -> [[Int]] {
        records
            .sorted { $0.timestamp < $1.timestamp }
            .map { [$0.inputTokens, $0.cacheReadTokens, $0.outputTokens] }
    }

    // MARK: - Tests

    /// Appending to a live session must bill only the new delta, and the result
    /// must match a from-scratch parse of the final file.
    func testIncrementalAppendMatchesFullParse() async throws {
        let name = "rollout-live.jsonl"
        try write(Self.head + Self.snapshot(2, input: 100, cached: 20, output: 30), to: name)

        let store = CodexUsageStore(directory: dir)
        let first = await store.scan().records
        XCTAssertEqual(fields(first), [[80, 20, 30]])

        // Session continues: cumulative totals grow.
        try append(Self.snapshot(3, input: 150, cached: 30, output: 45), to: name)
        let second = await store.scan().records
        XCTAssertEqual(fields(second), [[80, 20, 30], [40, 10, 15]])

        try append(Self.snapshot(4, input: 220, cached: 55, output: 70), to: name)
        let third = await store.scan().records

        // Ground truth: the stateless collector re-parsing the finished file.
        let full = CodexParser.parseFile(at: dir.appendingPathComponent(name))
        XCTAssertEqual(fields(third), fields(full))
        XCTAssertEqual(third.count, full.count)
    }

    /// A rescan with nothing changed on disk must re-read no bytes and return
    /// the identical record set — this is the path that runs every 60s.
    func testUnchangedRescanIsStable() async throws {
        let name = "rollout-idle.jsonl"
        try write(Self.head
            + Self.snapshot(2, input: 100, cached: 20, output: 30)
            + Self.snapshot(3, input: 150, cached: 30, output: 45), to: name)

        let store = CodexUsageStore(directory: dir)
        let first = await store.scan().records
        let second = await store.scan().records
        let third = await store.scan().records

        XCTAssertEqual(fields(first), [[80, 20, 30], [40, 10, 15]])
        XCTAssertEqual(fields(second), fields(first))
        XCTAssertEqual(fields(third), fields(first))
    }

    /// A half-written trailing line must not be consumed; it should be picked up
    /// once the writer completes it.
    func testPartialTrailingLineIsDeferred() async throws {
        let name = "rollout-partial.jsonl"
        try write(Self.head + Self.snapshot(2, input: 100, cached: 20, output: 30), to: name)

        let store = CodexUsageStore(directory: dir)
        let initial = await store.scan().records
        XCTAssertEqual(fields(initial), [[80, 20, 30]])

        // Torn write: no trailing newline yet.
        let partial = Self.snapshot(3, input: 150, cached: 30, output: 45)
            .trimmingCharacters(in: .newlines)
        try append(String(partial.prefix(partial.count / 2)), to: name)
        let torn = await store.scan().records
        XCTAssertEqual(fields(torn), [[80, 20, 30]], "partial line must be ignored")

        // Writer finishes the line.
        try append(String(partial.suffix(partial.count - partial.count / 2)) + "\n", to: name)
        let completed = await store.scan().records
        XCTAssertEqual(fields(completed), [[80, 20, 30], [40, 10, 15]])
    }

    /// Non-OpenAI providers and internal support models contribute nothing, and
    /// stay excluded across rescans.
    func testRejectedSessionsStayExcluded() async throws {
        try write("""
        {"timestamp":"2026-07-13T10:00:00Z","type":"session_meta","payload":{"model_provider":"anthropic"}}
        {"timestamp":"2026-07-13T10:00:01Z","type":"turn_context","payload":{"model":"gpt-5.5"}}
        \(Self.snapshot(2, input: 100, cached: 20, output: 30))
        """, to: "rollout-other-provider.jsonl")

        try write("""
        {"timestamp":"2026-07-13T10:00:00Z","type":"session_meta","payload":{"model_provider":"openai"}}
        {"timestamp":"2026-07-13T10:00:01Z","type":"turn_context","payload":{"model":"codex-auto-review"}}
        \(Self.snapshot(2, input: 100, cached: 20, output: 30))
        """, to: "rollout-auto-review.jsonl")

        let store = CodexUsageStore(directory: dir)
        let first = await store.scan().records
        let second = await store.scan().records
        XCTAssertTrue(first.isEmpty)
        XCTAssertTrue(second.isEmpty)

        try append(Self.snapshot(3, input: 150, cached: 30, output: 45), to: "rollout-auto-review.jsonl")
        let afterGrowth = await store.scan().records
        XCTAssertTrue(afterGrowth.isEmpty, "rejected sessions must stay rejected after growth")
    }

    /// Snapshots that arrive before the model is known must still be billed once
    /// `turn_context` shows up in a later chunk.
    func testDeltasBeforeModelIsKnownAreFlushedLater() async throws {
        let name = "rollout-late-model.jsonl"
        try write("""
        {"timestamp":"2026-07-13T10:00:00Z","type":"session_meta","payload":{"model_provider":"openai"}}
        \(Self.snapshot(2, input: 100, cached: 20, output: 30))
        """, to: name)

        let store = CodexUsageStore(directory: dir)
        let beforeModel = await store.scan().records
        XCTAssertTrue(beforeModel.isEmpty, "no model yet → nothing priceable")

        try append("""
        {"timestamp":"2026-07-13T10:00:03Z","type":"turn_context","payload":{"model":"gpt-5.5"}}

        """, to: name)
        let flushed = await store.scan().records
        XCTAssertEqual(fields(flushed), [[80, 20, 30]])
        XCTAssertEqual(flushed.map(\.model), ["gpt-5.5"])

        // And it still agrees with a full parse of the finished file.
        XCTAssertEqual(fields(flushed), fields(CodexParser.parseFile(at: dir.appendingPathComponent(name))))
    }

    /// A truncated/rotated file is re-read from scratch rather than producing
    /// bogus deltas against stale cumulative totals.
    func testTruncationTriggersFullReread() async throws {
        let name = "rollout-rotated.jsonl"
        try write(Self.head
            + Self.snapshot(2, input: 100, cached: 20, output: 30)
            + Self.snapshot(3, input: 150, cached: 30, output: 45), to: name)

        let store = CodexUsageStore(directory: dir)
        let before = await store.scan().records
        XCTAssertEqual(fields(before).count, 2)

        // Rotated: same path, smaller content, fresh session.
        try write(Self.head + Self.snapshot(2, input: 10, cached: 0, output: 5), to: name)
        let after = await store.scan().records
        XCTAssertEqual(fields(after), [[10, 0, 5]])
    }

    /// The `changed` flag drives whether `AppModel` re-dedups and re-prices the
    /// whole history, so it must be false exactly when nothing was ingested.
    func testChangedFlagTracksIngestion() async throws {
        let name = "rollout-flag.jsonl"
        try write(Self.head + Self.snapshot(2, input: 100, cached: 20, output: 30), to: name)

        let store = CodexUsageStore(directory: dir)
        let first = await store.scan()
        XCTAssertTrue(first.changed, "first scan ingests")

        let idle = await store.scan()
        XCTAssertFalse(idle.changed, "nothing on disk moved")
        XCTAssertEqual(fields(idle.records), fields(first.records))

        try append(Self.snapshot(3, input: 150, cached: 30, output: 45), to: name)
        let grown = await store.scan()
        XCTAssertTrue(grown.changed, "file grew")

        let idleAgain = await store.scan()
        XCTAssertFalse(idleAgain.changed)

        try FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        let deleted = await store.scan()
        XCTAssertTrue(deleted.changed, "deletion changes the record set")
    }

    /// Records for deleted session files must not linger forever.
    func testDeletedFilesArePruned() async throws {
        let name = "rollout-doomed.jsonl"
        try write(Self.head + Self.snapshot(2, input: 100, cached: 20, output: 30), to: name)

        let store = CodexUsageStore(directory: dir)
        let present = await store.scan().records
        XCTAssertEqual(present.count, 1)

        try FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        let afterDelete = await store.scan().records
        XCTAssertTrue(afterDelete.isEmpty)
    }
}
