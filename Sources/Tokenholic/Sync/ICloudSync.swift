import Foundation
import Combine

/// Entitlement-free cross-device sync via the iCloud Drive folder.
///
/// Each device writes ONLY its own `<deviceId>.json` into
/// `~/Library/Mobile Documents/com~apple~CloudDocs/Tokenholic/` (single-writer
/// invariant → no conflicts) and reads all peers' files to aggregate. Robustness
/// per the verified design: gate on the ubiquity token, coordinate every read
/// (uncoordinated reads of dataless files can fail with EDEADLK), trigger
/// downloads for not-yet-downloaded peers, and do all I/O off the main thread.
@MainActor
final class ICloudSync: ObservableObject {
    @Published private(set) var peers: [DeviceSnapshot] = []   // other devices only
    @Published private(set) var available = false

    private let folderName = "Tokenholic"
    private var baseURL: URL?
    private var watcher: DirectoryWatcher?
    private var timer: Timer?
    private var writeItem: DispatchWorkItem?
    private let ioQueue = DispatchQueue(label: "ai.conol.Tokenholic.icloud", qos: .utility)
    private let writeDebounce: TimeInterval = 10
    private let scanInterval: TimeInterval = 60

    /// iCloud Drive root → our folder. nil when iCloud Drive is unavailable.
    nonisolated static var folderURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Tokenholic", isDirectory: true)
    }

    func start() {
        guard FileManager.default.ubiquityIdentityToken != nil else {
            available = false
            return
        }
        let base = Self.folderURL
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        baseURL = base
        available = true

        // Peer changes (incl. a download completing) land as FS events.
        watcher = DirectoryWatcher(paths: [base.path]) { [weak self] in
            Task { @MainActor in self?.scan() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: scanInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scan() }
        }
        scan()
    }

    // MARK: - Write (this device's own file only)

    func publish(_ snapshot: DeviceSnapshot) {
        guard available, let base = baseURL else { return }
        writeItem?.cancel()
        let item = DispatchWorkItem { Self.write(snapshot, to: base) }
        writeItem = item
        ioQueue.asyncAfter(deadline: .now() + writeDebounce, execute: item)
    }

    /// Write immediately (e.g. on quit), bypassing the debounce.
    func flush(_ snapshot: DeviceSnapshot?) {
        guard available, let base = baseURL, let snapshot else { return }
        writeItem?.cancel()
        ioQueue.async { Self.write(snapshot, to: base) }
    }

    // MARK: - Read + aggregate (peers)

    private func scan() {
        guard let base = baseURL else { return }
        let ownId = DeviceIdentity.id
        ioQueue.async { [weak self] in
            let found = Self.scanPeers(base: base, ownId: ownId)
            Task { @MainActor in self?.peers = found }
        }
    }

    // MARK: - Codable helpers

    nonisolated static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
    nonisolated static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    // MARK: - Coordinated file I/O (off-main; nonisolated)

    nonisolated static func write(_ snapshot: DeviceSnapshot, to base: URL) {
        guard let data = try? makeEncoder().encode(snapshot) else { return }
        let target = base.appendingPathComponent("\(snapshot.deviceId).json")
        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        coordinator.coordinate(writingItemAt: target, options: .forReplacing, error: &coordError) { url in
            try? data.write(to: url, options: .atomic) // atomic = temp + rename in-dir
        }
    }

    /// Read every `<id>.json` except our own, returning the freshest snapshot
    /// per deviceId. Dataless peers are download-triggered and picked up next scan.
    nonisolated static func scanPeers(base: URL, ownId: String) -> [DeviceSnapshot] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: base,
            includingPropertiesForKeys: [.ubiquitousItemDownloadingStatusKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let decoder = makeDecoder()
        let coordinator = NSFileCoordinator()
        var byId: [String: DeviceSnapshot] = [:]

        for url in entries where url.pathExtension == "json" {
            if url.deletingPathExtension().lastPathComponent == ownId { continue } // single-writer: skip self

            // Trigger download for not-yet-local files; read them on a later scan.
            let status = (try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?
                .ubiquitousItemDownloadingStatus
            if let status, status != .current, status != .downloaded {
                try? fm.startDownloadingUbiquitousItem(at: url)
                continue
            }

            var data: Data?
            var coordError: NSError?
            coordinator.coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordError) { u in
                data = try? Data(contentsOf: u)
            }
            guard let data,
                  let snapshot = try? decoder.decode(DeviceSnapshot.self, from: data),
                  snapshot.schemaVersion <= DeviceSnapshot.currentSchemaVersion
            else { continue }

            if let existing = byId[snapshot.deviceId], existing.lastUpdated >= snapshot.lastUpdated { continue }
            byId[snapshot.deviceId] = snapshot
        }
        return Array(byId.values)
    }
}
