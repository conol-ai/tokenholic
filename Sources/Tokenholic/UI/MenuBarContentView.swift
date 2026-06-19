import SwiftUI
import AppKit

/// The popover shown when the menubar item is clicked.
///
/// Phosphor-on-charcoal layout: a branded header, the headline net-earnings
/// number with the API-vs-plan breakdown, a glowing daily-value sparkline,
/// expandable per-tool cards, the session / 7-day windows, and a slim action bar.
struct MenuBarContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let version = model.updateVersion {
                updateBanner(version)
            }

            hero

            if model.dailyAPICost.count >= 2,
               model.dailyAPICost.contains(where: { $0.apiCostUSD > 0 }) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Daily API value this cycle")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.inkDim)
                    SparklineView(points: model.dailyAPICost)
                }
            }

            if model.toolSummaries.isEmpty {
                emptyState
            } else {
                VStack(spacing: 9) {
                    ForEach(model.toolSummaries) { ToolCard(summary: $0) }
                    windowCard(
                        icon: GlyphTile(systemName: "bolt.fill", tint: Palette.amber),
                        title: "This session", window: model.session,
                        detail: sessionDetail, emptyText: "no active session"
                    )
                    windowCard(
                        icon: GlyphTile(systemName: "calendar", tint: Palette.blue),
                        title: "Past 7 days", window: model.week,
                        detail: weekDetail, emptyText: "—"
                    )
                }
            }

            if model.syncAvailable {
                if model.isSignedIn { devicesCard } else { signInCard }
            }

            if !model.unpricedModels.isEmpty {
                unpricedWarning
            }

            footer
        }
        .padding(16)
        .frame(width: 360)
        .background(PopoverBackground())
        .environment(\.colorScheme, .dark)
        .foregroundStyle(Palette.ink)
        .tint(Palette.green)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            BrandMark(size: 30)
            Text("Tokenholic")
                .font(.system(size: 15.5, weight: .semibold))
                .foregroundStyle(Palette.ink)
            Spacer(minLength: 0)
            overflowMenu
        }
    }

    private var overflowMenu: some View {
        Menu {
            Button("Check for Updates…") { model.checkForUpdates() }
            if model.syncAvailable {
                Divider()
                Toggle("Menu bar shows all devices", isOn: $model.menubarUsesCombined)
                if model.isSignedIn {
                    Button("Sign out of sync") { model.signOut() }
                }
            }
            Divider()
            Text("Tokenholic v\(appVersion)")
        } label: {
            overflowLabel
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var overflowLabel: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Palette.inkDim)
            .frame(width: 28, height: 28)
            .background(Circle().fill(Palette.card))
            .overlay(Circle().strokeBorder(Palette.stroke, lineWidth: 1))
            .contentShape(Circle())
    }

    // MARK: - Hero

    private var hero: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Earned this billing cycle")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.inkDim)
                Text(CurrencyFormat.signed(model.blendedNetUSD))
                    .font(.system(size: 39, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.money(model.blendedNetUSD))
                    .shadow(color: Palette.money(model.blendedNetUSD).opacity(0.45), radius: 14)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: model.blendedNetUSD)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .layoutPriority(1)
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 5) {
                HStack(spacing: 6) {
                    Text("vs. API rates")
                        .foregroundStyle(Palette.inkDim)
                    Text(CurrencyFormat.usd(model.blendedMonthlyAPICostUSD))
                        .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Palette.ink)
                }
                HStack(spacing: 6) {
                    Text("−\u{200A}" + CurrencyFormat.usd(model.blendedSubscriptionUSD))
                        .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Palette.amber)
                    Text("plan")
                        .foregroundStyle(Palette.inkDim)
                }
            }
            .font(.system(size: 11.5))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.top, 20)
        }
    }

    // MARK: - Window (session / week) cards

    private func windowCard(icon: GlyphTile, title: String, window: UsageWindow?,
                            detail: [(String, String)], emptyText: String) -> some View {
        let hasData = (window?.recordCount ?? 0) > 0
        let subtitle = hasData
            ? "\(CurrencyFormat.tokens(window!.tokens)) tokens / \(CurrencyFormat.usd(window!.apiCostUSD)) value"
            : emptyText
        return ExpandableRow(
            title: title, subtitle: subtitle,
            value: nil, valueColor: Palette.green,
            canExpand: hasData,
            icon: { icon },
            detail: { DetailGrid(rows: detail) }
        )
    }

    private var sessionDetail: [(String, String)] {
        guard let s = model.session else { return [] }
        var rows: [(String, String)] = []
        if let started = sessionSubtitle { rows.append(("Started", started)) }
        rows.append(("API value", CurrencyFormat.usd(s.apiCostUSD)))
        rows.append(("Messages", "\(s.recordCount)"))
        return rows
    }

    private var weekDetail: [(String, String)] {
        guard let w = model.week else { return [] }
        return [
            ("API value", CurrencyFormat.usd(w.apiCostUSD)),
            ("Tokens", CurrencyFormat.tokens(w.tokens)),
            ("Messages", "\(w.recordCount)"),
        ]
    }

    private var sessionSubtitle: String? {
        guard let start = model.session?.start else { return nil }
        let elapsed = Date().timeIntervalSince(start)
        guard elapsed > 0 else { return nil }
        let hours = Int(elapsed) / 3600
        let minutes = (Int(elapsed) % 3600) / 60
        return "\(hours)h \(minutes)m ago"
    }

    // MARK: - Sync

    private var devicesCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("Across your devices", systemImage: "rectangle.stack")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.inkDim)
                Spacer()
                Text("net")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.inkFaint)
                Text(CurrencyFormat.signed(model.combinedNetUSD))
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Palette.money(model.combinedNetUSD))
            }
            ForEach(model.deviceRows) { row in
                HStack(spacing: 7) {
                    Image(systemName: row.isSelf ? "checkmark.circle.fill" : "desktopcomputer")
                        .font(.system(size: 11))
                        .foregroundStyle(row.isSelf ? Palette.green : Palette.inkFaint)
                    Text(row.name).foregroundStyle(Palette.ink).lineLimit(1)
                    if row.isStale {
                        Text("· stale").foregroundStyle(Palette.amber)
                    }
                    Spacer()
                    Text(CurrencyFormat.usd(row.apiCostUSD))
                        .monospacedDigit()
                        .foregroundStyle(Palette.inkDim)
                }
                .font(.system(size: 11.5))
            }
            HStack {
                Text("\(CurrencyFormat.tokens(model.combinedTokens)) tokens · \(model.signedInEmail ?? "signed in")")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.inkFaint)
                    .lineLimit(1)
                Spacer()
                Button("Sign out") { model.signOut() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Palette.green)
            }
        }
        .cardSurface()
    }

    private var signInCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(Palette.green)
                Text("Sync across your devices")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Palette.ink)
            }
            Text("Sign in so every device's usage rolls into one combined total.")
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.inkDim)
                .fixedSize(horizontal: false, vertical: true)
            // Google sign-in stays hidden until the Google provider is configured.
            Button {
                model.signIn(.github)
            } label: {
                Label("Sign in with GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            .buttonStyle(GhostButtonStyle())
        }
        .cardSurface()
    }

    // MARK: - Misc states

    private var emptyState: some View {
        HStack(spacing: 10) {
            if model.status == .loading {
                ProgressView().controlSize(.small)
                Text("Reading Claude Code logs…").foregroundStyle(Palette.inkDim)
            } else {
                Image(systemName: "tray").foregroundStyle(Palette.inkFaint)
                Text("No usage found in this billing cycle yet.").foregroundStyle(Palette.inkDim)
            }
        }
        .font(.system(size: 12.5))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 20)
    }

    private func updateBanner(_ version: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(Palette.green)
            VStack(alignment: .leading, spacing: 1) {
                Text("Update available")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text(version)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.inkDim)
            }
            Spacer()
            if model.isDownloadingUpdate {
                ProgressView().controlSize(.small)
            } else {
                Button("Get") { model.downloadUpdate() }
                    .buttonStyle(PhosphorButtonStyle())
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Palette.green.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Palette.green.opacity(0.28), lineWidth: 1)
        )
    }

    private var unpricedWarning: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Palette.amber)
            Text("Unpriced: \(model.unpricedModels.joined(separator: ", "))")
                .font(.system(size: 11))
                .foregroundStyle(Palette.inkDim)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Palette.amber.opacity(0.10))
        )
    }

    // MARK: - Footer action bar

    private var footer: some View {
        VStack(spacing: 8) {
            Rectangle().fill(Palette.strokeSoft).frame(height: 1)
            HStack {
                FooterButton(title: "Refresh", icon: "arrow.clockwise") { model.refreshNow() }
                Spacer()
                FooterButton(title: "Settings", icon: "gearshape") { openSettings() }
                Spacer()
                FooterButton(title: "Quit", tint: Palette.red) { NSApplication.shared.terminate(nil) }
            }
            if let updated = model.lastUpdated {
                Text("Updated \(updated.formatted(date: .omitted, time: .shortened)) · v\(appVersion)")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.inkFaint)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "settings")
    }
}

// MARK: - Tool card

/// One tool's monthly earnings, expandable to reveal the API/plan/message split.
private struct ToolCard: View {
    let summary: ToolSummary

    var body: some View {
        ExpandableRow(
            title: summary.tool.displayName,
            subtitle: "\(CurrencyFormat.tokens(summary.inputTokens)) in · "
                + "\(CurrencyFormat.tokens(summary.outputTokens)) out · "
                + "\(CurrencyFormat.tokens(summary.cacheReadTokens)) cache",
            value: CurrencyFormat.signed(summary.netUSD),
            valueColor: Palette.money(summary.netUSD),
            canExpand: true,
            icon: { ToolIcon(tool: summary.tool) },
            detail: {
                DetailGrid(rows: [
                    ("API value", CurrencyFormat.usd(summary.monthlyAPICostUSD)),
                    ("Your plan", "−" + CurrencyFormat.usd(summary.subscriptionUSD)),
                    ("Cache read", CurrencyFormat.tokens(summary.cacheReadTokens)),
                    ("Cache written", CurrencyFormat.tokens(summary.cacheWriteTokens)),
                    ("Messages", "\(summary.recordCount)"),
                ])
            }
        )
    }
}

// MARK: - Reusable expandable card row

/// A tappable card: icon tile + title/subtitle + optional money value + chevron,
/// disclosing a detail grid when expanded.
private struct ExpandableRow<Icon: View, Detail: View>: View {
    let title: String
    let subtitle: String
    var value: String?
    var valueColor: Color = Palette.green
    var canExpand: Bool = true
    @ViewBuilder var icon: () -> Icon
    @ViewBuilder var detail: () -> Detail

    @State private var open = false
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                icon()
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.inkDim)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 4)
                HStack(spacing: 7) {
                    if let value {
                        Text(value)
                            .font(.system(size: 13.5, weight: .semibold).monospacedDigit())
                            .foregroundStyle(valueColor)
                    }
                    if canExpand {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.inkFaint)
                            .rotationEffect(.degrees(open ? 90 : 0))
                    }
                }
            }
            if open && canExpand {
                detail()
                    .padding(.top, 10)
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(hovering ? Palette.cardHi : Palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Palette.stroke, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            guard canExpand else { return }
            withAnimation(.snappy(duration: 0.22)) { open.toggle() }
        }
        .onHover { hovering = $0 }
        .onChange(of: canExpand) { _, expandable in
            if !expandable { open = false }
        }
    }
}

/// A two-column label/value grid shown inside an expanded card.
private struct DetailGrid: View {
    let rows: [(String, String)]

    var body: some View {
        VStack(spacing: 6) {
            Rectangle().fill(Palette.strokeSoft).frame(height: 1)
            ForEach(rows.indices, id: \.self) { i in
                HStack {
                    Text(rows[i].0).foregroundStyle(Palette.inkDim)
                    Spacer()
                    Text(rows[i].1).foregroundStyle(Palette.ink).monospacedDigit()
                }
                .font(.system(size: 11.5))
            }
        }
    }
}

/// A footer action: an icon+label button that highlights on hover.
private struct FooterButton: View {
    let title: String
    var icon: String?
    var tint: Color = Palette.inkDim
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                }
                Text(title).font(.system(size: 12.5, weight: .medium))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(hover ? 0.06 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

private extension View {
    /// Standard card chrome: padded, filled, hairline-bordered rounded rectangle.
    func cardSurface() -> some View {
        padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Palette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(Palette.stroke, lineWidth: 1)
            )
    }
}
