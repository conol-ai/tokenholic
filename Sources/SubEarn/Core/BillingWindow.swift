import Foundation

/// Computes the start of the current monthly subscription cycle.
///
/// The user picks a billing anchor day (1–28). The current cycle starts at the
/// most recent occurrence of that day at local midnight, on or before `now`.
enum BillingWindow {
    static func currentCycleStart(anchorDay: Int, now: Date, calendar: Calendar) -> Date {
        let clampedAnchor = min(max(anchorDay, 1), 28)
        let parts = calendar.dateComponents([.year, .month], from: now)

        var comps = DateComponents()
        comps.year = parts.year
        comps.month = parts.month
        comps.day = clampedAnchor
        comps.hour = 0
        comps.minute = 0
        comps.second = 0

        guard let thisMonthAnchor = calendar.date(from: comps) else { return now }
        if thisMonthAnchor <= now {
            return thisMonthAnchor
        }
        // Anchor hasn't occurred yet this month → cycle began last month.
        return calendar.date(byAdding: .month, value: -1, to: thisMonthAnchor) ?? thisMonthAnchor
    }
}
