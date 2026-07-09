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

            // Peak delight: only ask people to brag/star when they're in the black.
            if model.blendedNetUSD > 0 {
                delightRow
            }

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

            // Cloud/social surfaces only exist when cloud mode is opted into.
            if model.cloudModeEnabled {
                if model.syncAvailable {
                    if model.isSignedIn { devicesCard } else { signInCard }
                }

                if model.socialAvailable && model.isSignedIn {
                    friendsTeaser
                }
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
        .onAppear {
            // Capture openWindow so an invite deep link can surface the window.
            InviteRouter.openSocial = {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "social")
            }
        }
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
            Button("Send feedback…") { Feedback.openNewIssue(hasUsage: !model.toolSummaries.isEmpty) }
            if model.cloudModeEnabled {
                if model.socialAvailable && model.isSignedIn {
                    Button("Friends & Leaderboard…") { openSocial() }
                }
                if model.syncAvailable {
                    Divider()
                    Toggle("Menu bar shows all devices", isOn: $model.menubarUsesCombined)
                    if model.isSignedIn {
                        Button("Sign out of sync") { model.signOut() }
                    }
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
            .overlay(alignment: .topTrailing) {
                if model.pendingRequestCount > 0 {
                    Circle().fill(Palette.amber).frame(width: 7, height: 7)
                        .overlay(Circle().strokeBorder(Palette.bg, lineWidth: 1.5))
                        .offset(x: 1, y: -1)
                }
            }
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
            Text("Sign in so every device's usage rolls into one combined total — and climb the daily leaderboard with friends.")
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

    // MARK: - Social teaser

    /// Compact entry point to the Friends & Leaderboard window, with a pending-
    /// request badge. The full social UI lives in its own resizable window.
    private var friendsTeaser: some View {
        Button(action: openSocial) {
            HStack(spacing: 11) {
                GlyphTile(systemName: "trophy.fill", tint: Palette.green, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Friends & leaderboard")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
                    Text(model.socialRankSubtitle)
                        .font(.system(size: 11)).foregroundStyle(Palette.inkDim).lineLimit(1)
                }
                Spacer(minLength: 4)
                if model.pendingRequestCount > 0 {
                    Text("\(model.pendingRequestCount)")
                        .font(.system(size: 10.5, weight: .bold)).foregroundStyle(Palette.bgDeep)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Palette.amber))
                }
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.inkFaint)
            }
            .padding(11)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Palette.card))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Palette.stroke, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Misc states

    @ViewBuilder private var emptyState: some View {
        // A genuine loading state during the first scan; the guided checklist
        // only after a completed scan finds zero records.
        if model.status == .idle || model.status == .loading {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Reading your usage logs…").foregroundStyle(Palette.inkDim)
            }
            .font(.system(size: 12.5))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 20)
        } else {
            guidedEmptyState
        }
    }

    private var toolProbes: [FirstRunGuide.Row] {
        let fm = FileManager.default
        let gemini = fm.fileExists(atPath: GeminiDataLocation.telemetryLog)
        return [
            .init(tool: .claudeCode,
                  detected: fm.fileExists(atPath: ClaudeDataLocation.projects.path),
                  note: "~/.claude/projects"),
            .init(tool: .codex,
                  detected: fm.fileExists(atPath: CodexDataLocation.sessions.path),
                  note: "~/.codex/sessions"),
            .init(tool: .geminiCli,
                  detected: gemini,
                  note: gemini ? "~/.gemini/telemetry.log" : "needs local telemetry"),
        ]
    }

    /// True when no tool has a plan price — earnings can't be computed until one is set.
    private var noPlanPriceSet: Bool {
        model.claudeMonthlyPriceUSD == 0
            && model.codexMonthlyPriceUSD == 0
            && model.geminiMonthlyPriceUSD == 0
    }

    private var guidedEmptyState: some View {
        FirstRunGuide(
            rows: toolProbes,
            showPlanNudge: noPlanPriceSet,
            onEnableGemini: openGeminiTelemetryDocs,
            onOpenSettings: openSettings,
            onFeedback: { Feedback.openNewIssue(hasUsage: false) }
        )
    }

    private func openGeminiTelemetryDocs() {
        if let url = URL(string: "https://google-gemini.github.io/gemini-cli/docs/cli/telemetry.html") {
            NSWorkspace.shared.open(url)
        }
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

    private func openSocial() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "social")
    }

    // MARK: - Peak-delight share / star

    /// A quiet share + star row, shown under the hero only when the user is in
    /// the black — the moment they're most willing to brag and to star the repo.
    private var delightRow: some View {
        HStack(spacing: 8) {
            FooterShareButton(text: shareText)
            FooterButton(title: "Star Tokenholic", icon: "star.fill", tint: Palette.green) { openRepo() }
            Spacer(minLength: 0)
        }
    }

    /// Pre-filled brag text using the live net number + the site URL.
    private var shareText: String {
        "My AI coding subscription is earning me \(CurrencyFormat.signed(model.blendedNetUSD))/mo "
        + "over what I pay for it 🤑 — priced at real API rates by Tokenholic. https://tokenholic.app"
    }

    private func openRepo() {
        if let url = URL(string: "https://github.com/conol-ai/tokenholic") {
            NSWorkspace.shared.open(url)
        }
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

/// First-run / empty-state activation guide: a calm, tool-aware checklist shown
/// when a completed scan finds zero usage, so a new user learns *why* they see
/// nothing and *what to do*. Presentational (data injected) so it renders in
/// isolation for snapshot tests.
struct FirstRunGuide: View {
    struct Row: Identifiable {
        let tool: Tool
        let detected: Bool
        let note: String
        var id: String { tool.rawValue }
    }
    let rows: [Row]
    let showPlanNudge: Bool
    var onEnableGemini: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var onFeedback: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "tray").foregroundStyle(Palette.inkFaint)
                Text("No usage in this cycle yet")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
            }
            Text("Tokenholic reads your local AI-coding logs and updates live the moment a session writes usage.")
                .font(.system(size: 11.5)).foregroundStyle(Palette.inkDim)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                ForEach(rows) { row in
                    HStack(spacing: 9) {
                        Image(systemName: row.detected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 12))
                            .foregroundStyle(row.detected ? Palette.green : Palette.inkFaint)
                        Text(row.tool.displayName)
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.ink)
                        Spacer(minLength: 6)
                        if row.tool == .geminiCli && !row.detected {
                            Button(action: onEnableGemini) {
                                Text("enable →")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Palette.green)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text(row.note)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(Palette.inkFaint)
                        }
                    }
                }
            }
            .padding(11)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Palette.card))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Palette.stroke, lineWidth: 1))

            if showPlanNudge {
                Button(action: onOpenSettings) {
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape")
                        Text("Set your plan price in Settings so we can compute earnings →")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.system(size: 11.5)).foregroundStyle(Palette.amber)
                }
                .buttonStyle(.plain)
            }

            Button(action: onFeedback) {
                Text("Something look off? Send feedback →")
                    .font(.system(size: 11)).foregroundStyle(Palette.inkFaint)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

/// The icon+label chrome shared by the footer's `FooterButton` and the
/// share-sheet trigger, so both read identically.
private struct FooterLabel: View {
    let title: String
    var icon: String?
    var tint: Color = Palette.inkDim
    var hover: Bool = false

    var body: some View {
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
            FooterLabel(title: title, icon: icon, tint: tint, hover: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// The macOS share sheet, wrapped so it wears the same chrome as `FooterButton`.
/// `ShareLink` presents the system picker without needing an NSView anchor —
/// menubar-agent friendly (no Dock activation surprise).
private struct FooterShareButton: View {
    let text: String
    var title: String = "Share earnings"
    var tint: Color = Palette.green

    @State private var hover = false

    var body: some View {
        ShareLink(item: text) {
            FooterLabel(title: title, icon: "square.and.arrow.up", tint: tint, hover: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

