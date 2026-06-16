import Foundation
import Combine
import AppKit

/// Lightweight auto-update via the public GitHub Releases API: checks the latest
/// release, compares to this build's version, and (on demand) downloads the
/// notarized DMG to ~/Downloads and opens it for a drag-install. No extra infra.
@MainActor
final class UpdateChecker: ObservableObject {
    struct Available: Equatable {
        let version: String
        let downloadURL: URL?
        let releaseURL: URL
    }

    @Published private(set) var available: Available?
    @Published private(set) var isDownloading = false

    private let repo = "conol-ai/tokenholic"
    private let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    private var timer: Timer?

    func start() {
        checkNow()
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkNow() }
        }
    }

    func checkNow() { Task { await check() } }

    /// One awaitable check (used by the `--check-update` CLI hook).
    func checkOnce() async { await check() }

    private func check() async {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Tokenholic", forHTTPHeaderField: "User-Agent") // GitHub requires a UA
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let release = try? JSONDecoder().decode(GitHubRelease.self, from: data)
        else { return }

        guard Self.isNewer(release.versionString, than: currentVersion) else {
            available = nil
            return
        }
        let dmg = release.assets.first { $0.name.lowercased().hasSuffix(".dmg") }
        available = Available(
            version: release.versionString,
            downloadURL: dmg.flatMap { URL(string: $0.browser_download_url) },
            releaseURL: URL(string: release.html_url) ?? url
        )
    }

    /// Download the DMG to ~/Downloads and open (mount) it; falls back to opening
    /// the release page in the browser.
    func downloadAndOpen() {
        guard let available else { return }
        guard let downloadURL = available.downloadURL else {
            NSWorkspace.shared.open(available.releaseURL)
            return
        }
        isDownloading = true
        Task {
            defer { isDownloading = false }
            do {
                let (tmp, _) = try await URLSession.shared.download(from: downloadURL)
                let dest = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Downloads/\(downloadURL.lastPathComponent)")
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: tmp, to: dest)
                NSWorkspace.shared.open(dest) // mounts the DMG
            } catch {
                NSWorkspace.shared.open(available.releaseURL)
            }
        }
    }

    /// Numeric, component-wise semver compare; tolerates a leading "v" and a
    /// "+build" suffix (our dev builds are like "0.1.0+abc1234").
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            var c = s
            if c.hasPrefix("v") { c.removeFirst() }
            let base = c.split(separator: "+").first.map(String.init) ?? c
            return base.split(separator: ".").map { Int($0) ?? 0 }
        }
        let pa = parts(a), pb = parts(b)
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

private struct GitHubRelease: Decodable {
    let tag_name: String
    let html_url: String
    let assets: [Asset]

    var versionString: String { tag_name.hasPrefix("v") ? String(tag_name.dropFirst()) : tag_name }

    struct Asset: Decodable {
        let name: String
        let browser_download_url: String
    }
}
