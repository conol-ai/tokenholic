import SwiftUI
import AppKit

/// The popover shown when the menubar item is clicked.
struct MenuBarContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let version = model.updateVersion {
                updateBanner(version)
            }
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

            if model.syncAvailable {
                Divider()
                if model.isSignedIn {
                    devicesSection
                } else {
                    signInSection
                }
            }

            if !model.unpricedModels.isEmpty {
                Label("Unpriced: \(model.unpricedModels.joined(separator: ", "))",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
    }

    // MARK: - Sections

    private func updateBanner(_ version: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill").foregroundStyle(.blue)
            Text("Update available: \(version)").font(.caption.bold())
            Spacer()
            if model.isDownloadingUpdate {
                ProgressView().controlSize(.small)
            } else {
                Button("Get") { model.downloadUpdate() }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.12)))
    }

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
                Label("Across your devices", systemImage: "rectangle.stack.person.crop")
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
            HStack {
                Text("\(CurrencyFormat.tokens(model.combinedTokens)) tokens · \(model.signedInEmail ?? "signed in")")
                    .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                Spacer()
                Button("Sign out") { model.signOut() }
                    .buttonStyle(.borderless).controlSize(.small)
            }
        }
    }

    private var signInSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sync across your devices")
                .font(.caption).foregroundStyle(.secondary)
            Text("Sign in so every device's usage rolls into one combined total.")
                .font(.caption2).foregroundStyle(.tertiary)
            HStack {
                Button { model.signIn(.google) } label: {
                    Label("Google", systemImage: "globe")
                }
                Button { model.signIn(.github) } label: {
                    Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }
            .buttonStyle(.bordered).controlSize(.small)
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

            Button {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")

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
