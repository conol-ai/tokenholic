import SwiftUI

/// The dedicated Friends & Leaderboard window (opened from the popover teaser).
/// Gates: signed-out → sign in; signed-in but no handle → claim one (the
/// explicit social opt-in); otherwise the Leaderboard / Friends tabs.
struct SocialView: View {
    @EnvironmentObject private var model: AppModel
    @State private var tab = Tab.leaderboard
    @State private var toast: Toast?

    enum Tab: String, CaseIterable { case leaderboard = "Leaderboard", friends = "Friends" }
    struct Toast: Equatable { let text: String; let isError: Bool }

    var body: some View {
        ZStack {
            PopoverBackground().ignoresSafeArea()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            if let toast { toastBanner(toast) }
        }
        .frame(width: 420, height: 600)
        .environment(\.colorScheme, .dark)
        .foregroundStyle(Palette.ink)
        .tint(Palette.green)
        .onChange(of: model.socialToast) { _, t in if let t { show(t.text, isError: t.isError) } }
    }

    @ViewBuilder private var content: some View {
        if !model.socialAvailable {
            centered { SocialPlaceholder(icon: "wifi.slash", title: "Sync not configured",
                message: "Friends & leaderboard need the Supabase backend configured for this build.") }
        } else if !model.isSignedIn {
            signedOut
        } else if !model.hasHandle {
            claimHandle
        } else {
            tabs
        }
    }

    // MARK: - Tabs

    private var tabs: some View {
        VStack(spacing: 0) {
            header
            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            .padding(.horizontal, 16).padding(.bottom, 10)
            ScrollView {
                Group {
                    switch tab {
                    case .leaderboard: LeaderboardView()
                    case .friends:     FriendsView()
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 18)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            BrandMark(size: 28)
            Text("Friends & Leaderboard")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.ink)
            Spacer()
            if let handle = model.myHandle {
                AvatarBadge(handle: handle, size: 26)
            }
        }
        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)
    }

    // MARK: - Signed-out gate

    private var signedOut: some View {
        centered {
            VStack(spacing: 14) {
                GlyphTile(systemName: "trophy.fill", tint: Palette.green, size: 46)
                Text("Climb the daily leaderboard")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.ink)
                Text("Sign in, add a few friends, and see who squeezed the most value out of their AI today.")
                    .font(.system(size: 12)).foregroundStyle(Palette.inkDim)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Button {
                    model.signIn(.github)
                } label: {
                    Label("Sign in with GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                .buttonStyle(PhosphorButtonStyle())
            }
            .frame(maxWidth: 300)
        }
    }

    // MARK: - Claim-handle gate (the social opt-in)

    private var claimHandle: some View {
        centered {
            ClaimHandleCard(suggestion: suggestedHandle) { handle in
                model.claimHandle(handle)
            }
        }
    }

    private var suggestedHandle: String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789_")
        let local = (model.signedInEmail ?? "").split(separator: "@").first.map(String.init) ?? ""
        var s = String(local.lowercased().filter { allowed.contains($0) })
        if s.count < 3 { s += "dev" }
        return String(s.prefix(30))
    }

    // MARK: - Toast

    private func show(_ text: String, isError: Bool) {
        let t = Toast(text: text, isError: isError)
        toast = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if toast == t { toast = nil }
        }
    }

    private func toastBanner(_ t: Toast) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: t.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(t.isError ? Palette.amber : Palette.green)
                Text(t.text).font(.system(size: 12)).foregroundStyle(Palette.ink).lineLimit(2)
            }
            .padding(.horizontal, 13).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Palette.bgDeep))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder((t.isError ? Palette.amber : Palette.green).opacity(0.35), lineWidth: 1))
            .padding(.bottom, 14)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .animation(.snappy, value: toast)
    }

    private func centered<C: View>(@ViewBuilder _ inner: () -> C) -> some View {
        VStack { Spacer(); inner(); Spacer() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
    }
}

/// First-run handle claim: a single field seeded from the GitHub identity.
private struct ClaimHandleCard: View {
    let suggestion: String
    let onClaim: (String) -> Void
    @State private var handle = ""

    var body: some View {
        VStack(spacing: 13) {
            GlyphTile(systemName: "at", tint: Palette.green, size: 46)
            Text("Pick your handle")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.ink)
            Text("This is how friends find and add you. 3–30 characters: letters, numbers, underscore.")
                .font(.system(size: 12)).foregroundStyle(Palette.inkDim)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 4) {
                Text("@").foregroundStyle(Palette.inkFaint)
                TextField("handle", text: $handle)
                    .textFieldStyle(.plain).foregroundStyle(Palette.ink)
                    .onSubmit(claim)
            }
            .font(.system(size: 14)).padding(.horizontal, 12).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Palette.bgDeep))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Palette.stroke, lineWidth: 1))
            Button("Join", action: claim)
                .buttonStyle(PhosphorButtonStyle())
                .disabled(handle.trimmingCharacters(in: .whitespaces).count < 3)
        }
        .frame(maxWidth: 320)
        .onAppear { if handle.isEmpty { handle = suggestion } }
    }

    private func claim() {
        let h = handle.trimmingCharacters(in: .whitespaces)
        guard h.count >= 3 else { return }
        onClaim(h)
    }
}
