import SwiftUI
import Charts

public struct SparkPoint: Identifiable, Sendable {
    public let id: Int
    public let value: Double

    public init(id: Int, value: Double) {
        self.id = id
        self.value = value
    }
}

/// Compact axis-less line + area chart for one (optionally two) series.
public struct Sparkline: View {
    public var points: [SparkPoint]
    /// Second series drawn as a plain line (e.g. network upload).
    public var secondary: [SparkPoint]
    /// Nil auto-scales to the visible window's max.
    public var yDomain: ClosedRange<Double>?
    /// Minimum ceiling of the auto-scaled domain, in the series' unit —
    /// keeps idle noise from rendering as dramatic peaks. The default suits
    /// bytes/s; pass a small floor for small-magnitude units like ms.
    public var autoDomainFloor: Double

    public init(
        points: [SparkPoint],
        secondary: [SparkPoint] = [],
        yDomain: ClosedRange<Double>? = nil,
        autoDomainFloor: Double = 10_000
    ) {
        self.points = points
        self.secondary = secondary
        self.yDomain = yDomain
        self.autoDomainFloor = autoDomainFloor
    }

    private var xDomain: ClosedRange<Int> {
        // Grow left-to-right for the first minute, then scroll.
        let lastID = max(points.last?.id ?? 0, secondary.last?.id ?? 0)
        return max(0, lastID - 59)...max(59, lastID)
    }

    public var body: some View {
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
        return 0...max(peak * 1.1, autoDomainFloor)
    }
}
