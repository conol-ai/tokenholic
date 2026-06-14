import Foundation

/// Row written to `device_snapshots` on upsert. Omits `user_id` (defaulted from
/// `auth.uid()`) and `updated_at` (server-stamped by a trigger) so a client can
/// neither forge ownership nor a freshness value.
struct DeviceSnapshotWrite: Encodable {
    let device_id: String
    let device_name: String
    let platform: String?
    let app_version: String?
    let schema_version: Int
    let window_start: Date?
    let tools: [DeviceToolTotal]

    init(_ snapshot: DeviceSnapshot) {
        device_id = snapshot.deviceId
        device_name = snapshot.deviceName
        platform = snapshot.platform
        app_version = snapshot.appVersion
        schema_version = snapshot.schemaVersion
        window_start = snapshot.windowStart
        tools = snapshot.tools
    }
}

/// Row read back from `device_snapshots`.
struct DeviceSnapshotRow: Decodable {
    let device_id: String
    let device_name: String
    let platform: String?
    let app_version: String?
    let schema_version: Int?
    let window_start: Date?
    let tools: [DeviceToolTotal]
    let updated_at: Date

    func toSnapshot() -> DeviceSnapshot {
        DeviceSnapshot(
            schemaVersion: schema_version ?? 1,
            deviceId: device_id,
            deviceName: device_name,
            platform: platform,
            appVersion: app_version,
            lastUpdated: updated_at,
            windowStart: window_start,
            tools: tools
        )
    }
}
