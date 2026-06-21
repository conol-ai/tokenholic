import SwiftUI

/// Phosphor-on-charcoal design tokens for the menubar popover.
///
/// Deliberately mirrors the website's OKLCH palette (tokenholic.app) so the app
/// and the marketing site read as one product: a near-black, faintly green-tinted
/// "terminal" surface with a phosphor-green profit accent and an amber "what you
/// pay" accent.
enum Palette {
    // Surfaces ------------------------------------------------------------
    /// Popover body — very dark teal-charcoal (sampled from the reference).
    static let bg        = Color(red: 0.063, green: 0.098, blue: 0.105)
    /// Recessed surface (chart well, deepening toward the footer).
    static let bgDeep    = Color(red: 0.035, green: 0.067, blue: 0.074)
    /// Card / tile fill — barely a lift off the body, the way the reference reads.
    static let card      = Color.white.opacity(0.028)
    /// Hover / pressed lift.
    static let cardHi    = Color.white.opacity(0.055)
    /// Hairline borders — a whisper, not a bright outline.
    static let stroke    = Color.white.opacity(0.045)
    static let strokeSoft = Color.white.opacity(0.030)

    // Ink -----------------------------------------------------------------
    static let ink       = Color(red: 0.94, green: 0.96, blue: 0.95)   // primary
    static let inkDim    = Color(red: 0.64, green: 0.68, blue: 0.66)   // secondary
    static let inkFaint  = Color(red: 0.55, green: 0.59, blue: 0.58)   // captions (AA on bg + card)

    // Accents -------------------------------------------------------------
    static let green     = Color(red: 0.36, green: 0.88, blue: 0.58)   // profit / phosphor
    static let greenDeep = Color(red: 0.20, green: 0.55, blue: 0.36)
    static let amber     = Color(red: 0.96, green: 0.76, blue: 0.36)   // the plan you pay
    static let blue      = Color(red: 0.42, green: 0.62, blue: 0.98)   // 7-day window
    static let orange    = Color(red: 0.93, green: 0.45, blue: 0.20)   // Claude
    static let red       = Color(red: 0.91, green: 0.39, blue: 0.26)   // Quit / loss

    /// Earnings tint: green in the black, red in the red.
    static func money(_ value: Double) -> Color { value >= 0 ? green : red }

    /// Stable accent for an avatar/handle. Uses a deterministic djb2 hash (NOT
    /// String.hashValue, which is randomized per launch) so a handle keeps the
    /// same color across sessions. Only ever picks from the existing accents.
    static func avatarTint(for key: String) -> Color {
        let accents = [green, amber, blue, orange]
        var hash: UInt64 = 5381
        for byte in key.lowercased().utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return accents[Int(hash % UInt64(accents.count))]
    }
}

/// The popover's full-bleed background: a dark base with a soft phosphor bloom at
/// the top and a gentle deepening toward the footer.
struct PopoverBackground: View {
    var body: some View {
        ZStack {
            Palette.bg
            RadialGradient(
                colors: [Palette.green.opacity(0.10), .clear],
                center: UnitPoint(x: 0.5, y: -0.06),
                startRadius: 0, endRadius: 300
            )
            LinearGradient(
                colors: [.clear, Palette.bgDeep.opacity(0.65)],
                startPoint: .center, endPoint: .bottom
            )
        }
    }
}

/// A solid phosphor-green pill button (the "Get" / "Sign in" call-to-action).
struct PhosphorButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Palette.bgDeep)
            .padding(.horizontal, 13)
            .padding(.vertical, 6)
            .background(Capsule().fill(Palette.green))
            .shadow(color: Palette.green.opacity(0.40), radius: 6, y: 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .contentShape(Capsule())
    }
}

/// A quiet bordered pill (secondary actions like GitHub sign-in).
struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 13)
            .padding(.vertical, 6)
            .background(Capsule().fill(Palette.card))
            .overlay(Capsule().strokeBorder(Palette.stroke, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Capsule())
    }
}

extension View {
    /// A 1px hairline rule in the soft-stroke color.
    func hairlineDivider() -> some View {
        overlay(alignment: .bottom) {
            Rectangle().fill(Palette.strokeSoft).frame(height: 1)
        }
    }

    /// Standard card chrome: padded, filled, hairline-bordered rounded rectangle.
    /// Shared by the popover and the social views.
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

/// An initial on a hashed, stable accent tile — structurally identical to
/// `GlyphTile`/`ToolIcon` (same corner math, same tint opacities). No remote
/// image fetch: privacy-first, offline, and zero new asset pipeline.
struct AvatarBadge: View {
    let handle: String?
    var size: CGFloat = 30

    private var initial: String {
        let h = (handle ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "@ ")).uppercased()
        return h.isEmpty ? "?" : String(h.prefix(1))
    }
    private var tint: Color { Palette.avatarTint(for: handle ?? "?") }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
            .fill(tint.opacity(0.15))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                    .strokeBorder(tint.opacity(0.20), lineWidth: 1)
            )
            .overlay(
                Text(initial)
                    .font(.system(size: size * 0.44, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
            )
            .frame(width: size, height: size)
    }
}

/// A small rank chip: gold / silver / bronze for 1–3, a plain faint number for
/// 4+. A light podium feel without literal podium graphics.
struct RankPill: View {
    let rank: Int

    private var tint: Color {
        switch rank {
        case 1:  return Palette.amber       // gold
        case 2:  return Palette.inkDim      // silver
        case 3:  return Palette.orange      // bronze
        default: return Palette.inkFaint
        }
    }
    private var isPodium: Bool { rank <= 3 }

    var body: some View {
        Text("\(rank)")
            .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(isPodium ? Palette.bgDeep : Palette.inkFaint)
            .frame(width: 22, height: 22)
            .background(Circle().fill(isPodium ? tint : Palette.card))
            .overlay(Circle().strokeBorder(isPodium ? tint.opacity(0.5) : Palette.stroke, lineWidth: 1))
    }
}
