import Foundation

/// Small formatting helpers for money and token counts.
enum CurrencyFormat {
    static func usd(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    /// Signed, 2-decimal, using a real minus sign: "+$142.18" / "−$3.10".
    static func signed(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : "−"
        return "\(sign)$" + String(format: "%.2f", abs(value))
    }

    /// Compact signed dollars for the tight menubar: "+$142" / "−$3".
    static func signedCompact(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : "−"
        return "\(sign)$" + String(Int(abs(value).rounded()))
    }

    /// Compact token counts: "1.2M", "345K", "812".
    static func tokens(_ n: Int) -> String {
        let v = Double(n)
        if v >= 1_000_000 { return String(format: "%.1fM", v / 1_000_000) }
        if v >= 1_000 { return String(format: "%.0fK", v / 1_000) }
        return String(n)
    }
}
