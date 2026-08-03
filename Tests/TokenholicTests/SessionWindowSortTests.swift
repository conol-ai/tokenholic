import Foundation
import XCTest
@testable import Tokenholic

/// `AppModel` keeps `records` sorted so `EarningsCalculator` can skip an
/// O(n log n) sort of the whole history on every recompute. These tests pin the
/// invariant that the fast path and the sorting path agree.
final class SessionWindowSortTests: XCTestCase {

    private func record(_ minutesAgo: Int, now: Date) -> UsageRecord {
        UsageRecord(
            tool: .claudeCode,
            timestamp: now.addingTimeInterval(TimeInterval(-minutesAgo * 60)),
            model: "claude-opus-5",
            inputTokens: 10,
            outputTokens: 5,
            cacheReadTokens: 0,
            cacheCreate5mTokens: 0,
            cacheCreate1hTokens: 0,
            dedupKey: nil,
            isSidechain: false,
            sessionId: "s",
            sourcePath: "/tmp/s.jsonl"
        )
    }

    /// presorted:true over ascending input must equal presorted:false over the
    /// same records in arbitrary order.
    func testPresortedMatchesUnsorted() {
        let now = Date()
        let cal = Calendar.current
        // Two clusters separated by a >5h gap, plus recent activity.
        let offsets = [700, 690, 680, 120, 90, 60, 30, 5]
        let ascending = offsets.sorted(by: >).map { record($0, now: now) }
        let shuffled = ascending.shuffled()

        let fast = SessionWindow.activeBlock(records: ascending, now: now, calendar: cal, presorted: true)
        let slow = SessionWindow.activeBlock(records: shuffled, now: now, calendar: cal, presorted: false)

        XCTAssertNotNil(fast)
        XCTAssertEqual(fast?.start, slow?.start)
        XCTAssertEqual(fast?.records.count, slow?.records.count)
        XCTAssertEqual(
            fast?.records.map(\.timestamp).sorted(),
            slow?.records.map(\.timestamp).sorted()
        )
    }

    /// An old-only history has no active block, on either path.
    func testStaleHistoryHasNoActiveBlock() {
        let now = Date()
        let cal = Calendar.current
        let ascending = [800, 700, 610].sorted(by: >).map { record($0, now: now) }

        XCTAssertNil(SessionWindow.activeBlock(records: ascending, now: now, calendar: cal, presorted: true))
        XCTAssertNil(SessionWindow.activeBlock(
            records: ascending.shuffled(), now: now, calendar: cal, presorted: false))
    }

    /// The full report must agree whether or not it is told the input is sorted.
    func testReportAgreesOnBothPaths() {
        let now = Date()
        let cal = Calendar.current
        let ascending = [700, 690, 300, 120, 60, 10].sorted(by: >).map { record($0, now: now) }
        var priced = ascending
        for i in priced.indices { priced[i].apiEquivalentCostUSD = 0.25 }

        let sortedReport = EarningsCalculator.report(
            records: priced, subscriptionPrice: { _ in 20 }, billingAnchorDay: 1,
            now: now, calendar: cal, recordsAreSorted: true)
        let unsortedReport = EarningsCalculator.report(
            records: priced.shuffled(), subscriptionPrice: { _ in 20 }, billingAnchorDay: 1,
            now: now, calendar: cal, recordsAreSorted: false)

        XCTAssertEqual(sortedReport.blendedNetUSD, unsortedReport.blendedNetUSD, accuracy: 1e-9)
        XCTAssertEqual(sortedReport.last5hCostUSD, unsortedReport.last5hCostUSD, accuracy: 1e-9)
        XCTAssertEqual(sortedReport.session?.start, unsortedReport.session?.start)
        XCTAssertEqual(sortedReport.week?.tokens, unsortedReport.week?.tokens)
        XCTAssertEqual(sortedReport.session?.tokens, unsortedReport.session?.tokens)
        XCTAssertEqual(sortedReport.session?.recordCount, unsortedReport.session?.recordCount)
    }
}
