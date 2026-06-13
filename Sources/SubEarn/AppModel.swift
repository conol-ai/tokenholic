import Foundation
import Combine

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
    @Published private(set) var dailyAPICost: [DailyPoint] = []
    @Published private(set) var unpricedModels: [String] = []
    @Published private(set) var menubarTitle: String = "$—"

    // Persisted settings (UI-editable) ------------------------------------
    @Published var claudeMonthlyPriceUSD: Double { didSet { persist(); recompute() } }
    @Published var codexMonthlyPriceUSD: Double { didSet { persist(); recompute() } }
    @Published var billingAnchorDay: Int { didSet { persist(); recompute() } }

    // Internal state -------------------------------------------------------
    private var records: [UsageRecord] = []
    private let store = ClaudeUsageStore()
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
        // Keep time-based windows current even with no file activity.
        timer = Timer.scheduledTimer(withTimeInterval: recomputeInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.recompute() }
        }
    }

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
        dailyAPICost = report.dailyAPICost
        unpricedModels = report.unpricedModels
        menubarTitle = CurrencyFormat.signedCompact(report.blendedNetUSD)
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(claudeMonthlyPriceUSD, forKey: Keys.claudePrice)
        defaults.set(codexMonthlyPriceUSD, forKey: Keys.codexPrice)
        defaults.set(billingAnchorDay, forKey: Keys.billingDay)
    }
}
