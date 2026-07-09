import SwiftUI
import EyrieCore

struct StatsPanelView: View {
    @Bindable var module: StatsModule

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if module.showCPU || module.showMemory {
                HStack(alignment: .top, spacing: 10) {
                    if module.showCPU { cpuColumn }
                    if module.showMemory { memoryColumn }
                }
            }
            if module.showNetwork { networkRow }
            if !module.showCPU && !module.showMemory && !module.showNetwork {
                Text("All metrics are hidden. Enable them in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { module.beginSampling() }
        .onDisappear { module.endSampling() }
    }

    private var cpuColumn: some View {
        MetricRow(label: "CPU", value: cpuText) {
            Sparkline(points: sparkPoints(\.cpuTotal), yDomain: 0...1)
        }
        .frame(maxWidth: .infinity)
    }

    private var memoryColumn: some View {
        MetricRow(label: "Memory", value: memoryText, indicator: pressureColor) {
            Sparkline(
                points: sparkPoints { $0.memoryTotalBytes == 0 ? nil : $0.memoryFraction },
                yDomain: 0...1
            )
        }
        .frame(maxWidth: .infinity)
    }

    private var networkRow: some View {
        MetricRow(label: "Network", value: networkText) {
            Sparkline(
                points: sparkPoints(\.downBytesPerSecond),
                secondary: sparkPoints(\.upBytesPerSecond)
            )
        }
    }

    private func sparkPoints(_ value: (MetricsSnapshot) -> Double?) -> [SparkPoint] {
        module.history.elements.compactMap { snapshot in
            value(snapshot).map { SparkPoint(id: snapshot.id, value: $0) }
        }
    }

    private var cpuText: String {
        guard let cpu = module.latest?.cpuTotal else { return "—" }
        return cpu.formatted(.percent.precision(.fractionLength(0)))
    }

    private var memoryText: String {
        guard let latest = module.latest, latest.memoryTotalBytes > 0 else { return "—" }
        let used = Int64(latest.memoryUsedBytes).formatted(.byteCount(style: .memory))
        let total = Int64(latest.memoryTotalBytes).formatted(.byteCount(style: .memory))
        return "\(used) / \(total)"
    }

    private var pressureColor: Color? {
        switch module.latest?.memoryPressure {
        case .normal: .green
        case .warning: .yellow
        case .critical: .red
        case nil: nil
        }
    }

    private var networkText: String {
        guard let latest = module.latest,
              let down = latest.downBytesPerSecond,
              let up = latest.upBytesPerSecond else { return "—" }
        return "↓ \(Self.rate(down))  ↑ \(Self.rate(up))"
    }

    private static func rate(_ bytesPerSecond: Double) -> String {
        Int64(bytesPerSecond).formatted(.byteCount(style: .memory)) + "/s"
    }
}

private struct MetricRow<Graph: View>: View {
    var label: String
    var value: String
    var indicator: Color?
    @ViewBuilder var graph: Graph

    init(label: String, value: String, indicator: Color? = nil, @ViewBuilder graph: () -> Graph) {
        self.label = label
        self.value = value
        self.indicator = indicator
        self.graph = graph()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let indicator {
                    Circle().fill(indicator).frame(width: 6, height: 6)
                }
                Text(value)
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            graph
        }
    }
}
