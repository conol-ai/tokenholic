import Foundation

/// Stable per-device identity for cross-device sync.
///
/// The id is a UUID generated once and persisted — NOT derived from hostname,
/// ComputerName (user-renamable), LocalHostName (collision suffixes), or
/// IOPlatformUUID (changes on hardware service). The name is display-only.
enum DeviceIdentity {
    private static let idKey = "deviceId"

    static var id: String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: idKey) { return existing }
        let fresh = UUID().uuidString
        defaults.set(fresh, forKey: idKey)
        return fresh
    }

    /// Human-readable computer name, for display only.
    static var name: String {
        Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    }

    static var platform: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
}
