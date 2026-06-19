import Foundation
import Combine
import AppKit

/// Owns the data pipeline and exposes everything the UI binds to.
///
/// File changes (FSEvents on the Claude + Codex data dirs) trigger an
/// incremental rescan + recompute; a 60s timer recomputes time-based windows
/// (last-5h, cycle rollover) even when no new data arrives. Settings edits
/// trigger a cheap recompute over loaded data.
@MainActor
final class AppModel: ObservableObject {
    enum Status: Equatable {
        case idle, loading, loaded
        case failed(String)
    }

    // Published outputs ----------------------------------------------------
    @Published private(set) var status: Status = .idle
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var toolSummaries: [ToolSummary] = []
    @Published private(set) var blendedNetUSD: Double = 0
    @Published private(set) var blendedMonthlyAPICostUSD: Double = 0
    @Published private(set) var blendedSubscriptionUSD: Double = 0
    @Published private(set) var last5hCostUSD: Double = 0
    @Published private(set) var session: UsageWindow?
    @Published private(set) var week: UsageWindow?
    @Published private(set) var dailyAPICost: [DailyPoint] = []
    @Published private(set) var unpricedModels: [String] = []
    @Published private(set) var menubarTitle: String = "$—"

    // Cross-device (Supabase) sync ----------------------------------------
    @Published private(set) var syncAvailable = false
    @Published private(set) var isSignedIn = false
    @Published private(set) var signedInEmail: String?
    @Published private(set) var deviceRows: [DeviceRow] = []
    @Published private(set) var combinedNetUSD: Double = 0
    @Published private(set) var combinedTokens: Int = 0

    // Auto-update -----------------------------------------------------------
    @Published private(set) var updateVersion: String?
    @Published private(set) var isDownloadingUpdate = false

    // Persisted settings (UI-editable) ------------------------------------
    @Published var claudeMonthlyPriceUSD: Double { didSet { persist(); recompute() } }
    @Published var codexMonthlyPriceUSD: Double { didSet { persist(); recompute() } }
    @Published var billingAnchorDay: Int { didSet { persist(); recompute() } }
    @Published var menubarUsesCombined: Bool { didSet { persist(); applyMenubarTitle() } }

    // Internal state -------------------------------------------------------
    private var records: [UsageRecord] = []
    private let store = ClaudeUsageStore()
    private let sync = SupabaseSync()
    private let updater = UpdateChecker()
    private var localSnapshot: DeviceSnapshot?
    private var cancellables = Set<AnyCancellable>()
    private var watcher: DirectoryWatcher?
    private var timer: Timer?
    private var priceTable: [String: ModelPrice] = [:]
    private var priceTableLoadedAt: Date?
    private var isRefreshing = false
    private let recomputeInterval: TimeInterval = 60

    private enum Keys {
        static let claudePrice = "claudeMonthlyPriceUSD"
        static let codexPrice = "codexMonthlyPriceUSD"
        static let billingDay = "billingAnchorDay"
        static let menubarCombined = "menubarUsesCombined"
    }

    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Keys.claudePrice) == nil {
            defaults.set(PlanDetector.claudeDefaultMonthlyPrice(), forKey: Keys.claudePrice)
        }
        if defaults.object(forKey: Keys.codexPrice) == nil {
            defaults.set(0, forKey: Keys.codexPrice) // opt-in: user sets their ChatGPT plan price
        }
        if defaults.object(forKey: Keys.billingDay) == nil {
            defaults.set(1, forKey: Keys.billingDay)
        }
        // didSet does not fire for assignments inside init.
        self.claudeMonthlyPriceUSD = defaults.double(forKey: Keys.claudePrice)
        self.codexMonthlyPriceUSD = defaults.double(forKey: Keys.codexPrice)
        self.billingAnchorDay = max(1, defaults.integer(forKey: Keys.billingDay))
        self.menubarUsesCombined = defaults.bool(forKey: Keys.menubarCombined)
        start()
    }

    // MARK: - Lifecycle

    private func start() {
        refreshNow()
        // Rescan whenever Claude or Codex writes new usage data.
        var watchPaths = [ClaudeDataLocation.projects.path]
        let codexPath = CodexDataLocation.sessions.path
        if FileManager.default.fileExists(atPath: codexPath) { watchPaths.append(codexPath) }
        watcher = DirectoryWatcher(paths: watchPaths) { [weak self] in
            Task { @MainActor in self?.refreshNow() }
        }
        // Periodic re-scan + recompute. Re-scanning (not just recomputing the
        // in-memory buckets) self-heals a missed/coalesced FSEvent — e.g. for a
        // deeply nested subdir (subagents/, workflows/) created long after the
        // watcher started — so freshly written usage is ingested within a minute
        // instead of waiting for the next delivered event. refresh() is
        // isRefreshing-guarded and the scan is incremental + off-main, so the
        // recurring tree enumeration is cheap.
        timer = Timer.scheduledTimer(withTimeInterval: recomputeInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshNow() }
        }
        // Cross-device sync (Supabase): publish our totals, observe peers + auth.
        sync.start()
        syncAvailable = sync.available
        sync.$peers.receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.combine() }.store(in: &cancellables)
        sync.$isSignedIn.receive(on: RunLoop.main)
            .sink { [weak self] value in self?.isSignedIn = value }.store(in: &cancellables)
        sync.$userEmail.receive(on: RunLoop.main)
            .sink { [weak self] value in self?.signedInEmail = value }.store(in: &cancellables)
        // Auto-update: poll GitHub Releases.
        updater.start()
        updater.$available.receive(on: RunLoop.main)
            .sink { [weak self] in self?.updateVersion = $0?.version }.store(in: &cancellables)
        updater.$isDownloading.receive(on: RunLoop.main)
            .sink { [weak self] in self?.isDownloadingUpdate = $0 }.store(in: &cancellables)
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.sync.flush(self.localSnapshot)
            }
        }
    }

    func signIn(_ provider: SupabaseSync.AuthProvider) { sync.signIn(provider) }
    func signOut() { sync.signOut() }
    func downloadUpdate() { updater.downloadAndOpen() }
    func checkForUpdates() { updater.checkNow() }

    func refreshNow() {
        Task { await refresh() }
    }

    func refresh() async {
        if isRefreshing { return }
        isRefreshing = true
        defer { isRefreshing = false }
        if status != .loaded { status = .loading }

        await ensurePriceTable()
        let claudeRaw = await store.scan()                      // actor: incremental, off-main
        let codexRaw = await Task.detached(priority: .utility) {
            (try? CodexCollector().collect()) ?? []
        }.value

        let engine = PricingEngine(table: priceTable)
        records = Normalizer.dedup(claudeRaw + codexRaw).map { record in
            var r = record
            r.apiEquivalentCostUSD = engine.cost(for: r)
            return r
        }
        lastUpdated = Date()
        status = .loaded
        recompute()
    }

    /// Load the price table once, then refresh at most daily (kept in memory so
    /// we don't re-parse 1.5MB of JSON on every file-change rescan).
    private func ensurePriceTable() async {
        let stale = priceTableLoadedAt.map { Date().timeIntervalSince($0) > 24 * 3600 } ?? true
        guard priceTable.isEmpty || stale else { return }
        let table = await Task.detached(priority: .utility) { PricingProvider.loadTable() }.value
        if !table.isEmpty {
            priceTable = table
            priceTableLoadedAt = Date()
        }
    }

    // MARK: - Earnings math

    private func subscriptionPrice(for tool: Tool) -> Double {
        switch tool {
        case .claudeCode: return claudeMonthlyPriceUSD
        case .codex: return codexMonthlyPriceUSD
        case .cursor: return 0 // not in v1
        }
    }

    private func recompute() {
        let report = EarningsCalculator.report(
            records: records,
            subscriptionPrice: { [self] in subscriptionPrice(for: $0) },
            billingAnchorDay: billingAnchorDay,
            now: Date(),
            calendar: .current
        )
        toolSummaries = report.summaries
        blendedMonthlyAPICostUSD = report.blendedMonthlyAPICostUSD
        blendedSubscriptionUSD = report.blendedSubscriptionUSD
        blendedNetUSD = report.blendedNetUSD
        last5hCostUSD = report.last5hCostUSD
        session = report.session
        week = report.week
        dailyAPICost = report.dailyAPICost
        unpricedModels = report.unpricedModels
        publishSnapshotAndCombine()
    }

    // MARK: - Cross-device aggregation

    private func publishSnapshotAndCombine() {
        let snapshot = DeviceSnapshot(
            deviceId: DeviceIdentity.id,
            deviceName: DeviceIdentity.name,
            platform: DeviceIdentity.platform,
            appVersion: DeviceIdentity.appVersion,
            lastUpdated: Date(),
            windowStart: BillingWindow.currentCycleStart(
                anchorDay: billingAnchorDay, now: Date(), calendar: .current),
            tools: toolSummaries.map {
                DeviceToolTotal(
                    tool: $0.tool.rawValue,
                    apiCostUSD: $0.monthlyAPICostUSD,
                    inputTokens: $0.inputTokens,
                    outputTokens: $0.outputTokens,
                    cacheReadTokens: $0.cacheReadTokens,
                    cacheWriteTokens: $0.cacheWriteTokens,
                    recordCount: $0.recordCount
                )
            }
        )
        localSnapshot = snapshot
        sync.publish(snapshot)
        combine()
    }

    /// Merge this device's in-memory totals with synced peers. Subscription is
    /// subtracted ONCE (you pay one plan), not per device.
    private func combine() {
        let peers = sync.peers
        var rows: [DeviceRow] = []
        if let localSnapshot { rows.append(DeviceRow(snapshot: localSnapshot, isSelf: true)) }
        rows.append(contentsOf: peers.map { DeviceRow(snapshot: $0, isSelf: false) })
        deviceRows = rows.sorted { $0.apiCostUSD > $1.apiCostUSD }

        var apiByTool: [Tool: Double] = [:]
        var tokens = 0
        let snapshots = (localSnapshot.map { [$0] } ?? []) + peers
        for snapshot in snapshots {
            for total in snapshot.tools {
                if let tool = Tool(rawValue: total.tool) {
                    apiByTool[tool, default: 0] += total.apiCostUSD
                }
                tokens += total.totalTokens
            }
        }
        combinedNetUSD = apiByTool.reduce(0) { $0 + $1.value - subscriptionPrice(for: $1.key) }
        combinedTokens = tokens
        applyMenubarTitle()
    }

    private func applyMenubarTitle() {
        let useCombined = menubarUsesCombined && deviceRows.count > 1
        menubarTitle = CurrencyFormat.signedCompact(useCombined ? combinedNetUSD : blendedNetUSD)
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(claudeMonthlyPriceUSD, forKey: Keys.claudePrice)
        defaults.set(codexMonthlyPriceUSD, forKey: Keys.codexPrice)
        defaults.set(billingAnchorDay, forKey: Keys.billingDay)
        defaults.set(menubarUsesCombined, forKey: Keys.menubarCombined)
    }
}
