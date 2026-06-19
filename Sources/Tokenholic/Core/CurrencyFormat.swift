import Foundation

/// Small formatting helpers for money and token counts.
enum CurrencyFormat {
    /// Thousands-grouped, 2-decimal formatter. Pinned to en_US so the "$" prefix,
    /// comma grouping, and "." decimal stay consistent regardless of system locale.
    private static let grouped: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        f.usesGroupingSeparator = true
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    private static func grouped(_ value: Double) -> String {
        grouped.string(from: value as NSNumber) ?? String(format: "%.2f", value)
    }

    static func usd(_ value: Double) -> String {
        "$" + grouped(value)
    }

    /// Signed, 2-decimal, grouped, using a real minus sign: "+$1,142.18" / "−$3.10".
    static func signed(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : "−"
        return "\(sign)$" + grouped(abs(value))
    }

    /// Compact signed dollars for the tight menubar: "+$142" / "−$3".
    static func signedCompact(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : "−"
        return "\(sign)$" + String(Int(abs(value).rounded()))
    }

    /// Compact token counts: "1.2M", "11M", "345K", "812".
    static func tokens(_ n: Int) -> String {
        let v = Double(n)
        if v >= 1_000_000 {
            let m = v / 1_000_000
            // Drop the redundant ".0" for whole millions ("11M", not "11.0M").
            return m == m.rounded() ? String(format: "%.0fM", m) : String(format: "%.1fM", m)
        }
        if v >= 1_000 { return String(format: "%.0fK", v / 1_000) }
        return String(n)
    }
}
