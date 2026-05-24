import SwiftUI
import Charts

struct PriceHistoryChart: View {
    let history: [PriceHistoryPoint]

    private var minPrice: Double { (history.map(\.market).min() ?? 0) * 0.9 }
    private var maxPrice: Double { (history.map(\.market).max() ?? 10) * 1.1 }

    var body: some View {
        Chart {
            ForEach(history) { point in
                LineMark(
                    x: .value("Date", shortDate(point.date)),
                    y: .value("Price", point.market)
                )
                .foregroundStyle(.red.gradient)
                .interpolationMethod(.catmullRom)

                AreaMark(
                    x: .value("Date", shortDate(point.date)),
                    yStart: .value("Min", minPrice),
                    yEnd: .value("Price", point.market)
                )
                .foregroundStyle(.red.opacity(0.12).gradient)
                .interpolationMethod(.catmullRom)
            }
        }
        .chartYScale(domain: minPrice...maxPrice)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                    .foregroundStyle(.secondary.opacity(0.3))
                AxisValueLabel {
                    if let d = value.as(Double.self) {
                        Text("$\(String(format: "%.2f", d))").font(.caption2)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: 7)) { _ in
                AxisGridLine().foregroundStyle(.clear)
                AxisValueLabel().font(.caption2)
            }
        }
    }

    private func shortDate(_ dateString: String) -> String {
        // "2026-04-23" → "Apr 23"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateString) else { return dateString }
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}
