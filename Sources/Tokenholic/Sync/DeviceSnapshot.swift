import Foundation

/// The per-tool billing-cycle totals one device contributes. API value + tokens
/// only — NOT net, because the subscription is paid once and subtracted once at
/// aggregation time.
struct DeviceToolTotal: Codable {
    let tool: String
    let apiCostUSD: Double
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheWriteTokens: Int
    let recordCount: Int

    var totalTokens: Int { inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens }
}

/// One device's synced summary (the JSON written to iCloud Drive). Flat and
/// forward-compatible: decoders ignore unknown keys; readers skip snapshots
/// whose schemaVersion exceeds what they understand.
struct DeviceSnapshot: Codable, Identifiable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = currentSchemaVersion
    let deviceId: String
    let deviceName: String
    var platform: String?
    var appVersion: String?
    let lastUpdated: Date
    var windowStart: Date?
    let tools: [DeviceToolTotal]

    var id: String { deviceId }
    var totalAPICostUSD: Double { tools.reduce(0) { $0 + $1.apiCostUSD } }
    var totalTokens: Int { tools.reduce(0) { $0 + $1.totalTokens } }
}

/// A row in the "Across your Macs" UI list.
struct DeviceRow: Identifiable {
    let id: String
    let name: String
    let apiCostUSD: Double
    let tokens: Int
    let lastUpdated: Date
    let isSelf: Bool

    /// Not seen in over a week → still counted, but flagged in the UI.
    var isStale: Bool { Date().timeIntervalSince(lastUpdated) > 7 * 24 * 3600 }

    init(snapshot: DeviceSnapshot, isSelf: Bool) {
        self.id = snapshot.deviceId
        self.name = snapshot.deviceName
        self.apiCostUSD = snapshot.totalAPICostUSD
        self.tokens = snapshot.totalTokens
        self.lastUpdated = snapshot.lastUpdated
        self.isSelf = isSelf
    }
}
