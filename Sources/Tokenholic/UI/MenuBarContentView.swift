import SwiftUI
import AppKit

/// The popover shown when the menubar item is clicked.
struct MenuBarContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showSettings = false
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if model.dailyAPICost.count >= 2 {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Daily API value this cycle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    SparklineView(points: model.dailyAPICost)
                }
            }

            Divider()

            if model.toolSummaries.isEmpty {
                emptyState
            } else {
                ForEach(model.toolSummaries) { summary in
                    ToolCardView(summary: summary)
                }
                windowsSection
            }

            if model.syncAvailable && model.deviceRows.count > 1 {
                Divider()
                devicesSection
            }

            if !model.unpricedModels.isEmpty {
                Label("Unpriced: \(model.unpricedModels.joined(separator: ", "))",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            Divider()
            settingsSection
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Earned this billing cycle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(CurrencyFormat.signed(model.blendedNetUSD))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(model.blendedNetUSD >= 0 ? Color.green : Color.red)
                    .contentTransition(.numericText())
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("vs. API rates")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(CurrencyFormat.usd(model.blendedMonthlyAPICostUSD))
                    .font(.callout.monospacedDigit())
                Text("− " + CurrencyFormat.usd(model.blendedSubscriptionUSD) + " plan")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var windowsSection: some View {
        VStack(spacing: 8) {
            windowRow(icon: "bolt.fill", tint: .yellow, title: "This session",
                      subtitle: sessionSubtitle, window: model.session,
                      emptyText: "no active session")
            windowRow(icon: "calendar", tint: .blue, title: "Past 7 days",
                      subtitle: nil, window: model.week, emptyText: "—")
        }
    }

    private func windowRow(icon: String, tint: Color, title: String,
                           subtitle: String?, window: UsageWindow?,
                           emptyText: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                if let subtitle {
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let window, window.recordCount > 0 {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(CurrencyFormat.tokens(window.tokens) + " tokens")
                        .monospacedDigit()
                    Text(CurrencyFormat.usd(window.apiCostUSD) + " value")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Text(emptyText).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }

    private var sessionSubtitle: String? {
        guard let start = model.session?.start else { return nil }
        let elapsed = Date().timeIntervalSince(start)
        guard elapsed > 0 else { return nil }
        let hours = Int(elapsed) / 3600
        let minutes = (Int(elapsed) % 3600) / 60
        return "started \(hours)h \(minutes)m ago"
    }

    private var devicesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Across your Macs", systemImage: "icloud")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(CurrencyFormat.signed(model.combinedNetUSD))
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(model.combinedNetUSD >= 0 ? Color.green : Color.red)
            }
            ForEach(model.deviceRows) { row in
                HStack(spacing: 6) {
                    Image(systemName: row.isSelf ? "checkmark.circle.fill" : "desktopcomputer")
                        .foregroundStyle(row.isSelf ? Color.green : Color.secondary)
                    Text(row.name).lineLimit(1)
                    if row.isStale {
                        Text("· stale").foregroundStyle(.orange)
                    }
                    Spacer()
                    Text(CurrencyFormat.usd(row.apiCostUSD))
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                .font(.caption2)
            }
            Text("\(CurrencyFormat.tokens(model.combinedTokens)) tokens combined · synced via iCloud")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private var emptyState: some View {
        HStack {
            if model.status == .loading {
                ProgressView().controlSize(.small)
                Text("Reading Claude Code logs…").foregroundStyle(.secondary)
            } else {
                Text("No usage found in this billing cycle yet.")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var settingsSection: some View {
        DisclosureGroup(isExpanded: $showSettings) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Claude plan, $/mo")
                    Spacer()
                    TextField("price", value: $model.claudeMonthlyPriceUSD, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 72)
                }
                HStack {
                    Text("ChatGPT/Codex plan, $/mo")
                    Spacer()
                    TextField("price", value: $model.codexMonthlyPriceUSD, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 72)
                }
                HStack {
                    Text("Billing day of month")
                    Spacer()
                    Stepper(value: $model.billingAnchorDay, in: 1...28) {
                        Text("\(model.billingAnchorDay)").monospacedDigit()
                    }
                    .labelsHidden()
                }
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            try LoginItem.setEnabled(newValue)
                        } catch {
                            launchAtLogin = LoginItem.isEnabled // revert on failure
                        }
                        if newValue, LoginItem.requiresApproval {
                            LoginItem.openSystemSettings()
                        }
                    }
                if model.syncAvailable {
                    Toggle("Menubar shows all-Macs total", isOn: $model.menubarUsesCombined)
                }
            }
            .font(.caption)
            .padding(.top, 6)
        } label: {
            Label("Settings", systemImage: "gearshape.fill").font(.caption)
        }
    }

    private var footer: some View {
        HStack {
            if let updated = model.lastUpdated {
                Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.refreshNow()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh now")

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("q")
        }
    }
}

/// One tool's monthly earnings card.
private struct ToolCardView: View {
    let summary: ToolSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(summary.tool.displayName)
                    .font(.subheadline.bold())
                Spacer()
                Text(CurrencyFormat.signed(summary.netUSD))
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(summary.netUSD >= 0 ? Color.green : Color.red)
            }
            HStack(spacing: 6) {
                Text("API " + CurrencyFormat.usd(summary.monthlyAPICostUSD))
                Text("·")
                Text("plan " + CurrencyFormat.usd(summary.subscriptionUSD))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            Text("\(CurrencyFormat.tokens(summary.inputTokens)) in · "
                 + "\(CurrencyFormat.tokens(summary.outputTokens)) out · "
                 + "\(CurrencyFormat.tokens(summary.cacheReadTokens)) cache · "
                 + "\(summary.recordCount) msgs")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.05)))
    }
}
