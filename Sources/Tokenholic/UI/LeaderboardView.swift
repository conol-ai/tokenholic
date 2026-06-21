import SwiftUI

/// The daily leaderboard — caller + accepted friends ranked by gross Daily API
/// value (never net). Binds to `AppModel.leaderboard` (one friendship-gated RPC
/// feeds it). Rendered in the phosphor-on-charcoal system.
struct LeaderboardView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if model.leaderboard.isEmpty {
                SocialPlaceholder(
                    icon: "trophy",
                    title: "No standings yet",
                    message: "Add a friend to start a daily board. Today's value is the API-equivalent worth of the tokens you each spent today."
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(model.leaderboard.enumerated()), id: \.element.id) { index, row in
                        LeaderRow(entry: row, rank: index + 1, prominent: index < 3)
                    }
                }
                if !model.shareDaily { hiddenNote }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Today's leaderboard")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.ink)
                Text("API value spent today · resets at local midnight")
                    .font(.system(size: 11)).foregroundStyle(Palette.inkFaint)
            }
            Spacer()
            Button(action: model.refreshLeaderboard) {
                Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain).foregroundStyle(Palette.inkDim)
            .help("Refresh standings")
        }
    }

    private var hiddenNote: some View {
        HStack(spacing: 7) {
            Image(systemName: "eye.slash").font(.system(size: 11)).foregroundStyle(Palette.amber)
            Text("You're hidden — friends can't see your total while sharing is off.")
                .font(.system(size: 11)).foregroundStyle(Palette.inkDim)
        }
        .padding(.top, 2)
    }
}

/// One ranked row: rank pill · avatar · name/handle · today's gross $ + tokens.
/// "You" gets a green hairline + faint green fill; #1 gets the hero's phosphor bloom.
private struct LeaderRow: View {
    let entry: LeaderboardRow
    let rank: Int
    var prominent: Bool = false
    @State private var hover = false

    private var name: String {
        if let dn = entry.display_name, !dn.isEmpty { return dn }
        if let h = entry.handle, !h.isEmpty { return "@\(h)" }
        return "Friend"
    }
    private var handleLine: String { entry.handle.map { "@\($0)" } ?? "—" }

    var body: some View {
        HStack(spacing: 11) {
            RankPill(rank: rank)
            AvatarBadge(handle: entry.handle, size: prominent ? 34 : 30)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    if entry.is_self {
                        Text("you").font(.system(size: 9.5, weight: .bold))
                            .padding(.horizontal, 5).padding(.vertical, 1.5)
                            .background(Capsule().fill(Palette.green.opacity(0.18)))
                            .foregroundStyle(Palette.green)
                    }
                }
                Text(handleLine)
                    .font(.system(size: 11)).foregroundStyle(Palette.inkFaint).lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 1) {
                Text(CurrencyFormat.usd(entry.api_value_usd))
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Palette.green)
                Text("\(CurrencyFormat.tokens(entry.tokens)) tokens")
                    .font(.system(size: 10.5)).foregroundStyle(Palette.inkFaint).monospacedDigit()
            }
        }
        .padding(.horizontal, 11).padding(.vertical, prominent ? 10 : 8)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(entry.is_self ? Palette.green.opacity(0.07)
                                    : (hover ? Palette.cardHi : Palette.card))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(entry.is_self ? Palette.green.opacity(0.35) : Palette.stroke, lineWidth: 1)
        )
        .shadow(color: rank == 1 ? Palette.green.opacity(0.18) : .clear, radius: 10)
        .onHover { hover = $0 }
    }
}

/// Shared empty / signed-out / error card for the social views.
struct SocialPlaceholder: View {
    let icon: String
    let title: String
    let message: String
    var tint: Color = Palette.inkDim

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 26)).foregroundStyle(tint.opacity(0.85))
            Text(title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Palette.ink)
            Text(message).font(.system(size: 11.5)).foregroundStyle(Palette.inkDim)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 26).padding(.horizontal, 18)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Palette.stroke, lineWidth: 1))
    }
}
