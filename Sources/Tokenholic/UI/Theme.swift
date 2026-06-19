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
}
