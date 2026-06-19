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
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let spokes = 12
            let inner = size.width * 0.05
            let outer = size.width * 0.44
            let width = size.width * 0.085
            for i in 0..<spokes {
                let a = (Double(i) / Double(spokes)) * 2 * .pi - .pi / 2
                var path = Path()
                path.move(to: CGPoint(x: c.x + cos(a) * inner, y: c.y + sin(a) * inner))
                path.addLine(to: CGPoint(x: c.x + cos(a) * outer, y: c.y + sin(a) * outer))
                ctx.stroke(
                    path,
                    with: .color(color),
                    style: StrokeStyle(lineWidth: width, lineCap: .round)
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
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let petal = size.width * 0.23      // petal-circle radius
            let offset = size.width * 0.19     // loops overlap into a six-fold knot
            let width = size.width * 0.08      // solid strands without merging into a blob
            for i in 0..<6 {
                let a = (Double(i) / 6) * 2 * .pi
                let pc = CGPoint(x: c.x + cos(a) * offset, y: c.y + sin(a) * offset)
                let rect = CGRect(x: pc.x - petal, y: pc.y - petal, width: petal * 2, height: petal * 2)
                ctx.stroke(
                    Circle().path(in: rect),
                    with: .color(color),
                    style: StrokeStyle(lineWidth: width)
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
