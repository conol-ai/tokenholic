import Foundation

/// Collapses duplicate records that the same logical API response can produce
/// across transcript files.
///
/// Records sharing a `dedupKey` are merged to one, with the tie-break verified
/// from ccusage's behavior: prefer the non-sidechain copy, then the one with
/// more total tokens. Records with no `dedupKey` pass through untouched.
enum Normalizer {
    static func dedup(_ records: [UsageRecord]) -> [UsageRecord] {
        var best: [String: UsageRecord] = [:]
        var passthrough: [UsageRecord] = []

        for record in records {
            guard let key = record.dedupKey else {
                passthrough.append(record)
                continue
            }
            if let existing = best[key] {
                best[key] = preferred(existing, record)
            } else {
                best[key] = record
            }
        }
        return Array(best.values) + passthrough
    }

    private static func preferred(_ a: UsageRecord, _ b: UsageRecord) -> UsageRecord {
        // 1. Prefer the main-chain record over a sidechain copy.
        if a.isSidechain != b.isSidechain {
            return a.isSidechain ? b : a
        }
        // 2. Otherwise prefer the larger-token record.
        return b.totalTokens > a.totalTokens ? b : a
    }
}
