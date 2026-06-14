import Foundation

/// Computes the active 5-hour "session" window the way Claude/Codex usage
/// limits work, using ccusage-style blocks: a block is anchored to the first
/// activity in it (floored to the hour) and spans 5 hours; a gap longer than
/// the window starts a new block.
enum SessionWindow {
    static let sessionDuration: TimeInterval = 5 * 3600

    /// The currently-active block, or nil if the latest block's 5h window has
    /// already elapsed (no active session right now).
    static func activeBlock(records: [UsageRecord], now: Date, calendar: Calendar) -> (start: Date, records: [UsageRecord])? {
        guard !records.isEmpty else { return nil }
        let sorted = records.sorted { $0.timestamp < $1.timestamp }

        var blockStart = floorToHour(sorted[0].timestamp, calendar)
        var blockRecords: [UsageRecord] = []
        var lastTimestamp = sorted[0].timestamp

        for record in sorted {
            let exceedsWindow = record.timestamp >= blockStart.addingTimeInterval(sessionDuration)
            let gapTooLarge = record.timestamp.timeIntervalSince(lastTimestamp) >= sessionDuration
            if exceedsWindow || gapTooLarge {
                blockStart = floorToHour(record.timestamp, calendar)
                blockRecords = []
            }
            blockRecords.append(record)
            lastTimestamp = record.timestamp
        }

        guard now < blockStart.addingTimeInterval(sessionDuration) else { return nil }
        return (blockStart, blockRecords)
    }

    private static func floorToHour(_ date: Date, _ calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month, .day, .hour], from: date)) ?? date
    }
}
