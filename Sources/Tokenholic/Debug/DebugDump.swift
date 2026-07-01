import Foundation

/// Hidden CLI mode (`Tokenholic --dump`) that runs the full pipeline synchronously
/// and prints a report to stdout. Used to verify numbers against ccusage
/// without needing to inspect the GUI.
enum DebugDump {
    static func run() {
        let table = PricingProvider.loadTable()
        let engine = PricingEngine(table: table)

        func priceAll(_ raw: [UsageRecord]) -> [UsageRecord] {
            Normalizer.dedup(raw).map { record in
                var r = record
                r.apiEquivalentCostUSD = engine.cost(for: r)
                return r
            }
        }

        let claudePriced = priceAll((try? ClaudeCollector().collect()) ?? [])
        let codexPriced = priceAll((try? CodexCollector().collect()) ?? [])
        let geminiPriced = priceAll((try? GeminiCliCollector().collect()) ?? [])
        let priced = claudePriced + codexPriced + geminiPriced

        let claudePrice = PlanDetector.claudeDefaultMonthlyPrice()
        let codexPrice = 0.0
        let now = Date()
        let calendar = Calendar.current
        let report = EarningsCalculator.report(
            records: priced,
            subscriptionPrice: { tool in
                switch tool {
                case .claudeCode: return claudePrice
                case .codex: return codexPrice
                case .geminiCli: return 0
                case .cursor: return 0
                }
            },
            billingAnchorDay: 1,
            now: now,
            calendar: calendar
        )
        let cycleStart = BillingWindow.currentCycleStart(anchorDay: 1, now: now, calendar: calendar)

        print("══════════ Tokenholic debug dump ══════════")
        print("Price table entries: \(table.count)")
        print("Detected Claude tier: \(PlanDetector.claudeRateLimitTier() ?? "unknown") → $\(claudePrice)/mo")
        print("Records — Claude: \(claudePriced.count)   Codex: \(codexPriced.count)")
        print("Billing cycle start: \(cycleStart)")
        print("")

        // All-time per-model breakdown (independent of cycle) for cross-checking
        // against `ccusage`, which reports lifetime totals.
        print("── All-time totals (every record, for ccusage cross-check) ──")
        var allTimeCost = 0.0
        struct Agg { var count = 0; var cost = 0.0; var input = 0; var output = 0; var cacheR = 0; var cacheW = 0 }
        var byModel: [String: Agg] = [:]
        for r in priced {
            let c = r.apiEquivalentCostUSD ?? 0
            allTimeCost += c
            var e = byModel[r.model] ?? Agg()
            e.count += 1; e.cost += c
            e.input += r.inputTokens; e.output += r.outputTokens
            e.cacheR += r.cacheReadTokens; e.cacheW += r.cacheCreate5mTokens + r.cacheCreate1hTokens
            byModel[r.model] = e
        }
        for (model, e) in byModel.sorted(by: { $0.value.cost > $1.value.cost }) {
            let flag = engine.price(for: model) != nil ? "" : "  ⚠️ UNPRICED"
            print("  \(model)  \(CurrencyFormat.usd(e.cost))  (\(e.count) msgs, in \(e.input) / out \(e.output) / cacheR \(e.cacheR) / cacheW \(e.cacheW))\(flag)")
        }
        print("  ALL-TIME API-equivalent cost: \(CurrencyFormat.usd(allTimeCost))")
        print("")

        // Incremental store cross-check (Claude only): scan twice (2nd scan must
        // add nothing) and confirm it agrees with the Claude full scan.
        let storeRaw = scanStoreTwice()
        let storeCost = priceAll(storeRaw).reduce(0.0) { $0 + ($1.apiEquivalentCostUSD ?? 0) }
        let claudeFullCost = claudePriced.reduce(0.0) { $0 + ($1.apiEquivalentCostUSD ?? 0) }
        let storeDeduped = Normalizer.dedup(storeRaw).count
        print("── Incremental store cross-check (Claude) ──")
        print("  store deduped: \(storeDeduped) (Δ\(storeDeduped - claudePriced.count) vs full)   cost: \(CurrencyFormat.usd(storeCost)) (Δ\(CurrencyFormat.signed(storeCost - claudeFullCost)))")
        print("")

        print("── Current billing cycle ──")
        for s in report.summaries {
            print("  \(s.tool.displayName): API \(CurrencyFormat.usd(s.monthlyAPICostUSD)) − plan \(CurrencyFormat.usd(s.subscriptionUSD)) = net \(CurrencyFormat.signed(s.netUSD))")
            print("      in \(s.inputTokens) / out \(s.outputTokens) / cacheRead \(s.cacheReadTokens) / cacheWrite \(s.cacheWriteTokens) over \(s.recordCount) msgs")
        }
        if let s = report.session {
            print("  This session (5h): \(CurrencyFormat.tokens(s.tokens)) tokens, \(CurrencyFormat.usd(s.apiCostUSD)) value, \(s.recordCount) msgs")
        } else {
            print("  This session (5h): no active session")
        }
        if let w = report.week {
            print("  Past 7 days: \(CurrencyFormat.tokens(w.tokens)) tokens, \(CurrencyFormat.usd(w.apiCostUSD)) value, \(w.recordCount) msgs")
        }
        if !report.unpricedModels.isEmpty {
            print("  ⚠️ Unpriced models: \(report.unpricedModels.joined(separator: ", "))")
        }
        print("")
        print("  BLENDED NET THIS CYCLE: \(CurrencyFormat.signed(report.blendedNetUSD))  → menubar \"\(CurrencyFormat.signedCompact(report.blendedNetUSD))\"")
        print("═════════════════════════════════════════")
    }

    /// Bridge the async `ClaudeUsageStore` to the synchronous CLI: scan twice
    /// (second scan exercises the offset cache) and return the records.
    private static func scanStoreTwice() -> [UsageRecord] {
        final class Box { var records: [UsageRecord] = [] }
        let box = Box()
        let semaphore = DispatchSemaphore(value: 0)
        let store = ClaudeUsageStore()
        Task {
            _ = await store.scan()
            box.records = await store.scan()
            semaphore.signal()
        }
        semaphore.wait()
        return box.records
    }
}
