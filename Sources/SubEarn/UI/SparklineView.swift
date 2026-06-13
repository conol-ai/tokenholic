import SwiftUI
import Charts

/// A compact daily-API-value bar chart for the popover.
struct SparklineView: View {
    let points: [DailyPoint]

    var body: some View {
        Chart(points) { point in
            BarMark(
                x: .value("Day", point.day, unit: .day),
                y: .value("API value", point.apiCostUSD)
            )
            .foregroundStyle(Color.green.gradient)
            .cornerRadius(2)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 46)
    }
}
