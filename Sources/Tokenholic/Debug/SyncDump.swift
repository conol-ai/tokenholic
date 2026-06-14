import Foundation

/// Hidden CLI mode (`Tokenholic --sync-dump`): scan the iCloud folder, print
/// every device snapshot found and the combined total. Reads ALL files (ownId
/// sentinel) so it surfaces this Mac's own file too, for verification.
enum SyncDump {
    static func run() {
        let base = ICloudSync.folderURL
        print("══════════ Tokenholic sync dump ══════════")
        print("Folder: \(base.path)")
        print("iCloud available: \(FileManager.default.ubiquityIdentityToken != nil)")
        print("Folder exists: \(FileManager.default.fileExists(atPath: base.path))")

        let snapshots = ICloudSync.scanPeers(base: base, ownId: "\u{0}none\u{0}")
        print("Devices found: \(snapshots.count)")
        print("")

        var apiByTool: [String: Double] = [:]
        var totalTokens = 0
        for s in snapshots.sorted(by: { $0.totalAPICostUSD > $1.totalAPICostUSD }) {
            print("  \(s.deviceName)  [\(s.deviceId.prefix(8))]  updated \(s.lastUpdated)")
            print("    \(CurrencyFormat.tokens(s.totalTokens)) tokens · \(CurrencyFormat.usd(s.totalAPICostUSD)) API value")
            for t in s.tools {
                apiByTool[t.tool, default: 0] += t.apiCostUSD
                totalTokens += t.totalTokens
            }
        }

        // Subscription counted ONCE (Claude tier-detected; Codex assumed $0 here).
        let claudePrice = PlanDetector.claudeDefaultMonthlyPrice()
        let combinedAPI = apiByTool.values.reduce(0, +)
        var net = 0.0
        for (tool, api) in apiByTool { net += api - (tool == Tool.claudeCode.rawValue ? claudePrice : 0) }

        print("")
        print("  COMBINED across \(snapshots.count) device(s): \(CurrencyFormat.tokens(totalTokens)) tokens, API \(CurrencyFormat.usd(combinedAPI)), net \(CurrencyFormat.signed(net))")
        print("═════════════════════════════════════════")
    }
}
