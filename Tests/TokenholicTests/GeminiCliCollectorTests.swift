import XCTest
@testable import Tokenholic

final class GeminiCliCollectorTests: XCTestCase {

    private func fixtureText() throws -> String {
        let url = Bundle.module.url(forResource: "gemini-telemetry", withExtension: "log", subdirectory: "Fixtures")
            ?? Bundle.module.url(forResource: "gemini-telemetry", withExtension: "log")
        let path = try XCTUnwrap(url, "fixture gemini-telemetry.log not found in test bundle")
        return try String(contentsOf: path, encoding: .utf8)
    }

    func testParsesApiResponseRecordsAndIgnoresOthers() throws {
        let records = GeminiCliCollector.parse(try fixtureText(), sourcePath: "fixture")

        // Two api_response events; the gemini_cli.config record is ignored.
        XCTAssertEqual(records.count, 2)
        XCTAssertTrue(records.allSatisfy { $0.tool == .geminiCli })

        let pro = try XCTUnwrap(records.first { $0.model == "gemini-2.5-pro" })
        // fresh input = 1500 − 300 cached; cache-read = 300; output = 400 + 100 thoughts
        XCTAssertEqual(pro.inputTokens, 1200)
        XCTAssertEqual(pro.cacheReadTokens, 300)
        XCTAssertEqual(pro.outputTokens, 500)
        XCTAssertEqual(pro.cacheCreate5mTokens, 0)
        XCTAssertEqual(pro.cacheCreate1hTokens, 0)
        XCTAssertEqual(pro.sessionId, "sess-abc")
        XCTAssertEqual(pro.sourcePath, "fixture")

        // Timestamp parsed from the ISO8601 event.timestamp (fractional seconds).
        let expected = ISO8601DateFormatter().date(from: "2026-07-01T13:23:42Z")!
        XCTAssertEqual(pro.timestamp.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 1.0)

        let flash = try XCTUnwrap(records.first { $0.model == "gemini-2.5-flash" })
        XCTAssertEqual(flash.inputTokens, 800)
        XCTAssertEqual(flash.cacheReadTokens, 0)
        XCTAssertEqual(flash.outputTokens, 250)

        // Stable dedup keys so re-reading the append-only log doesn't double count.
        XCTAssertNotNil(pro.dedupKey)
        XCTAssertNotEqual(pro.dedupKey, flash.dedupKey)
    }

    func testEmptyOrGarbageInputYieldsNoRecords() {
        XCTAssertTrue(GeminiCliCollector.parse("", sourcePath: "x").isEmpty)
        XCTAssertTrue(GeminiCliCollector.parse("not json at all {{{", sourcePath: "x").isEmpty)
    }
}
