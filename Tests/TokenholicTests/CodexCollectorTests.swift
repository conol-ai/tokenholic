import Foundation
import XCTest
@testable import Tokenholic

final class CodexCollectorTests: XCTestCase {

    func testParsesUserSessionTokenDeltas() throws {
        let records = try parseSession(model: "gpt-5.5")

        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.map(\.model), ["gpt-5.5", "gpt-5.5"])
        XCTAssertEqual(records.map(\.inputTokens), [80, 40])
        XCTAssertEqual(records.map(\.cacheReadTokens), [20, 10])
        XCTAssertEqual(records.map(\.outputTokens), [30, 15])
    }

    func testIgnoresInternalAutoReviewSession() throws {
        XCTAssertTrue(try parseSession(model: "codex-auto-review").isEmpty)
    }

    private func parseSession(model: String) throws -> [UsageRecord] {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rollout-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }

        let jsonl = """
        {"timestamp":"2026-07-13T10:00:00Z","type":"session_meta","payload":{"model_provider":"openai"}}
        {"timestamp":"2026-07-13T10:00:01Z","type":"turn_context","payload":{"model":"\(model)"}}
        {"timestamp":"2026-07-13T10:00:02Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":20,"output_tokens":30}}}}
        {"timestamp":"2026-07-13T10:00:03Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":150,"cached_input_tokens":30,"output_tokens":45}}}}
        """
        try jsonl.write(to: url, atomically: true, encoding: .utf8)
        return CodexParser.parseFile(at: url)
    }
}
