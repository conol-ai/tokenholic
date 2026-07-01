import SwiftUI

/// The Tokenholic logo tile: a green shell-prompt glyph on a softly lit square.
struct BrandMark: View {
    var size: CGFloat = 30

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.07), Color.white.opacity(0.015)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(Palette.green.opacity(0.30), lineWidth: 1)
            )
            .overlay(
                Text(">_")
                    .font(.system(size: size * 0.40, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Palette.green)
                    .shadow(color: Palette.green.opacity(0.55), radius: 5)
                    .offset(y: -size * 0.01)
            )
            .frame(width: size, height: size)
    }
}

/// Claude's radial "sunburst" mark — tapered orange spokes around a center.
struct ClaudeBurst: View {
    var color: Color = Palette.orange

    var body: some View {
        Canvas { ctx, size in
            // Explicit CGFloat typing throughout: mixing CGFloat (size) with the
            // Double results of cos/sin/.pi makes the type-checker time out on
            // older toolchains (Swift 6.1 / CI).
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let spokes = 12
            let inner: CGFloat = size.width * 0.05
            let outer: CGFloat = size.width * 0.44
            let lineWidth: CGFloat = size.width * 0.085
            for i in 0..<spokes {
                let angle: Double = (Double(i) / Double(spokes)) * 2.0 * .pi - .pi / 2.0
                let dx: CGFloat = CGFloat(cos(angle))
                let dy: CGFloat = CGFloat(sin(angle))
                let start = CGPoint(x: center.x + dx * inner, y: center.y + dy * inner)
                let end = CGPoint(x: center.x + dx * outer, y: center.y + dy * outer)
                var path = Path()
                path.move(to: start)
                path.addLine(to: end)
                ctx.stroke(
                    path,
                    with: .color(color),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
            }
        }
    }
}

/// An OpenAI-style blossom — six interlocking rounded loops.
struct OpenAIMark: View {
    var color: Color = Color(white: 0.93)

    var body: some View {
        Canvas { ctx, size in
            // Explicit CGFloat typing — see ClaudeBurst for why.
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let petal: CGFloat = size.width * 0.23      // petal-circle radius
            let offset: CGFloat = size.width * 0.19     // loops overlap into a six-fold knot
            let lineWidth: CGFloat = size.width * 0.08  // solid strands without merging into a blob
            for i in 0..<6 {
                let angle: Double = (Double(i) / 6.0) * 2.0 * .pi
                let px: CGFloat = center.x + CGFloat(cos(angle)) * offset
                let py: CGFloat = center.y + CGFloat(sin(angle)) * offset
                let rect = CGRect(x: px - petal, y: py - petal, width: petal * 2, height: petal * 2)
                ctx.stroke(
                    Circle().path(in: rect),
                    with: .color(color),
                    style: StrokeStyle(lineWidth: lineWidth)
                )
            }
        }
    }
}

/// A tool's brand icon on a rounded tile (used in the per-tool cards).
struct ToolIcon: View {
    let tool: Tool
    var size: CGFloat = 40

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
            .fill(tileFill)
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                    .strokeBorder(Palette.stroke, lineWidth: 1)
            )
            .overlay(mark.frame(width: size * 0.62, height: size * 0.62))
            .frame(width: size, height: size)
    }

    @ViewBuilder private var mark: some View {
        switch tool {
        case .claudeCode: ClaudeBurst()
        case .codex:      OpenAIMark()
        case .geminiCli:
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(Color(red: 0.56, green: 0.62, blue: 0.98))
        case .cursor:
            Image(systemName: "cursorarrow.rays")
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(Palette.blue)
        }
    }

    private var tileFill: Color {
        switch tool {
        // Near-neutral dark tiles, matching the reference (the glyph carries the color).
        case .claudeCode: return Color.white.opacity(0.05)
        case .codex:      return Color.white.opacity(0.05)
        case .geminiCli:  return Color.white.opacity(0.05)
        case .cursor:     return Color.white.opacity(0.05)
        }
    }
}

/// A tinted SF Symbol on a rounded tile (used in the window/summary rows).
struct GlyphTile: View {
    let systemName: String
    let tint: Color
    var size: CGFloat = 40

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
            .fill(tint.opacity(0.15))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                    .strokeBorder(tint.opacity(0.20), lineWidth: 1)
            )
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(tint)
            )
            .frame(width: size, height: size)
    }
}
