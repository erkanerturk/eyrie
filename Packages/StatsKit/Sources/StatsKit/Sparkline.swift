import SwiftUI
import Charts

struct SparkPoint: Identifiable {
    let id: Int
    let value: Double
}

/// Compact axis-less line + area chart for one (optionally two) series.
struct Sparkline: View {
    var points: [SparkPoint]
    /// Second series drawn as a plain line (e.g. network upload).
    var secondary: [SparkPoint] = []
    /// Nil auto-scales to the visible window's max.
    var yDomain: ClosedRange<Double>?

    private var xDomain: ClosedRange<Int> {
        // Grow left-to-right for the first minute, then scroll.
        let lastID = max(points.last?.id ?? 0, secondary.last?.id ?? 0)
        return max(0, lastID - 59)...max(59, lastID)
    }

    var body: some View {
        Chart {
            ForEach(points) { point in
                AreaMark(x: .value("Tick", point.id), y: .value("Value", point.value))
                    .foregroundStyle(
                        .linearGradient(
                            colors: [Color.accentColor.opacity(0.3), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                LineMark(x: .value("Tick", point.id), y: .value("Value", point.value))
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            ForEach(secondary) { point in
                LineMark(x: .value("Tick", point.id), y: .value("Up", point.value), series: .value("Series", "secondary"))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain ?? autoDomain)
        .chartLegend(.hidden)
        .animation(nil, value: points.count)
        .frame(height: 30)
    }

    private var autoDomain: ClosedRange<Double> {
        let peak = (points.map(\.value) + secondary.map(\.value)).max() ?? 0
        // Floor keeps idle noise from rendering as dramatic peaks.
        return 0...max(peak * 1.1, 10_000)
    }
}
