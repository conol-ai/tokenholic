import SwiftUI
import Charts

/// A compact daily-API-value chart for the popover: a glowing phosphor line over
/// a soft gradient area fill, the way the reference design renders it.
struct SparklineView: View {
    let points: [DailyPoint]

    var body: some View {
        Chart(points) { point in
            AreaMark(
                x: .value("Day", point.day, unit: .day),
                yStart: .value("Base", 0),
                yEnd: .value("API value", point.apiCostUSD)
            )
            .interpolationMethod(.linear)
            .foregroundStyle(
                LinearGradient(
                    colors: [Palette.green.opacity(0.32), Palette.green.opacity(0.02)],
                    startPoint: .top, endPoint: .bottom
                )
            )

            LineMark(
                x: .value("Day", point.day, unit: .day),
                y: .value("API value", point.apiCostUSD)
            )
            .interpolationMethod(.linear)
            .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            .foregroundStyle(Palette.green)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: 62)
        .shadow(color: Palette.green.opacity(0.35), radius: 6, y: 1)
    }
}
