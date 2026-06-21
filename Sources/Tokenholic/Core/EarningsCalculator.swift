import Foundation

/// Pure aggregation: given priced records + settings, produce the earnings
/// report for the current monthly billing cycle. No I/O, no side effects —
/// shared by `AppModel` (UI) and `DebugDump` (CLI verification).
enum EarningsCalculator {
    static func report(
        records: [UsageRecord],
        subscriptionPrice: (Tool) -> Double,
        billingAnchorDay: Int,
        now: Date,
        calendar: Calendar
    ) -> EarningsReport {
        let cycleStart = BillingWindow.currentCycleStart(
            anchorDay: billingAnchorDay, now: now, calendar: calendar)
        let fiveHoursAgo = now.addingTimeInterval(-5 * 3600)

        var report = EarningsReport()
        var unpriced = Set<String>()
        var dailyTotals: [Date: Double] = [:]
        var dailyTokens: [Date: Int] = [:]

        for tool in Tool.allCases {
            let toolRecords = records.filter { $0.tool == tool }
            guard !toolRecords.isEmpty else { continue }

            // Last-5h value is a pure value metric — count it for every tool.
            report.last5hCostUSD += toolRecords
                .filter { $0.timestamp >= fiveHoursAgo }
                .reduce(0.0) { $0 + ($1.apiEquivalentCostUSD ?? 0) }

            let cycle = toolRecords.filter { $0.timestamp >= cycleStart }
            let sub = subscriptionPrice(tool)
            // Surface a tool (card + blended) only if it was used this cycle or
            // is paid-for; an idle, unpriced tool would add noise / phantom drag.
            guard !cycle.isEmpty || sub > 0 else { continue }

            let cost = cycle.reduce(0.0) { $0 + ($1.apiEquivalentCostUSD ?? 0) }
            for r in cycle where r.apiEquivalentCostUSD == nil { unpriced.insert(r.model) }

            report.summaries.append(ToolSummary(
                id: tool.rawValue,
                tool: tool,
                monthlyAPICostUSD: cost,
                subscriptionUSD: sub,
                inputTokens: cycle.reduce(0) { $0 + $1.inputTokens },
                outputTokens: cycle.reduce(0) { $0 + $1.outputTokens },
                cacheReadTokens: cycle.reduce(0) { $0 + $1.cacheReadTokens },
                cacheWriteTokens: cycle.reduce(0) { $0 + $1.cacheCreate5mTokens + $1.cacheCreate1hTokens },
                recordCount: cycle.count
            ))

            report.blendedMonthlyAPICostUSD += cost
            report.blendedSubscriptionUSD += sub

            for r in cycle {
                let day = calendar.startOfDay(for: r.timestamp)
                dailyTotals[day, default: 0] += (r.apiEquivalentCostUSD ?? 0)
                dailyTokens[day, default: 0] += r.totalTokens
            }
        }

        report.summaries.sort { $0.monthlyAPICostUSD > $1.monthlyAPICostUSD }
        report.unpricedModels = unpriced.sorted()
        report.dailyAPICost = dailyTotals
            .map { DailyPoint(day: $0.key, apiCostUSD: $0.value, tokens: dailyTokens[$0.key] ?? 0) }
            .sorted { $0.day < $1.day }

        // Active 5h session window (blended across tools).
        if let block = SessionWindow.activeBlock(records: records, now: now, calendar: calendar) {
            report.session = UsageWindow.from(
                block.records,
                start: block.start,
                end: block.start.addingTimeInterval(SessionWindow.sessionDuration)
            )
        }

        // Rolling 7-day window.
        let weekStart = now.addingTimeInterval(-7 * 24 * 3600)
        report.week = UsageWindow.from(
            records.filter { $0.timestamp >= weekStart },
            start: weekStart,
            end: now
        )

        return report
    }
}
