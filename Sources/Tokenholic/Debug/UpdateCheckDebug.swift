import Foundation

/// Hidden CLI mode (`Tokenholic --check-update`): runs one update check against
/// the live GitHub Releases API and prints the result. Self-contained and
/// off-main (no @MainActor) so it can block on a semaphore without deadlocking.
/// The bare CLI binary has no bundle version ("0"), so any release reads as
/// newer — exercising fetch → decode → version-compare → asset-extraction.
enum UpdateCheckDebug {
    static func run() {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            defer { semaphore.signal() }
            guard let url = URL(string: "https://api.github.com/repos/conol-ai/tokenholic/releases/latest") else { return }
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Tokenholic", forHTTPHeaderField: "User-Agent")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = obj["tag_name"] as? String
            else { print("check failed (network or unexpected response)"); return }

            let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let assets = (obj["assets"] as? [[String: Any]]) ?? []
            let dmg = assets.first { ($0["name"] as? String)?.lowercased().hasSuffix(".dmg") == true }
            let downloadURL = dmg?["browser_download_url"] as? String

            if UpdateChecker.isNewer(version, than: "0") {
                print("✅ Update detected: \(version)")
                print("   download: \(downloadURL ?? "(no .dmg asset)")")
                print("   release:  \(obj["html_url"] as? String ?? "?")")
            } else {
                print("No update (latest \(version) not newer than current).")
            }
        }
        semaphore.wait()
    }
}
