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
        MetricRow(label: "CPU", value: cpuText, showsGraph: module.showGraphs) {
            Sparkline(points: sparkPoints(\.cpuTotal), yDomain: 0...1)
        }
        .frame(maxWidth: .infinity)
    }

    private var memoryColumn: some View {
        MetricRow(label: "Memory", value: memoryText, indicator: pressureTone,
                  showsGraph: module.showGraphs) {
            Sparkline(
                points: sparkPoints { $0.memoryTotalBytes == 0 ? nil : $0.memoryFraction },
                yDomain: 0...1
            )
        }
        .frame(maxWidth: .infinity)
    }

    private var networkRow: some View {
        MetricRow(label: "Network", value: networkText, showsGraph: module.showGraphs) {
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

    /// "12,4 / 32 GB" — the unit is written once. Repeating it cost enough
    /// width to trigger the row's `minimumScaleFactor` and shrink the text.
    private var memoryText: String {
        guard let latest = module.latest, latest.memoryTotalBytes > 0 else { return "—" }
        let gibibyte: UInt64 = 1024 * 1024 * 1024
        // Every Mac this app runs on has gigabytes of RAM; below that the
        // shared unit would be wrong, so fall back to spelling both out.
        guard latest.memoryTotalBytes >= gibibyte else {
            let used = Int64(latest.memoryUsedBytes).formatted(.byteCount(style: .memory))
            let total = Int64(latest.memoryTotalBytes).formatted(.byteCount(style: .memory))
            return "\(used) / \(total)"
        }
        let scale = Double(gibibyte)
        let used = (Double(latest.memoryUsedBytes) / scale)
            .formatted(.number.precision(.fractionLength(1)))
        let total = (Double(latest.memoryTotalBytes) / scale)
            .formatted(.number.precision(.fractionLength(0)))
        return "\(used) / \(total) GB"
    }

    /// Uses the app-wide tone vocabulary so a memory warning looks like every
    /// other warning in the app.
    private var pressureTone: StatusTone? {
        switch module.latest?.memoryPressure {
        case .normal: .normal
        case .warning: .caution
        case .critical: .critical
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
    var indicator: StatusTone?
    var showsGraph: Bool
    /// Held unevaluated: building a `Sparkline` means mapping the whole 60
    /// sample history, and that must not happen when the graph is hidden.
    var graph: () -> Graph

    init(label: String, value: String, indicator: StatusTone? = nil, showsGraph: Bool = true,
         @ViewBuilder graph: @escaping () -> Graph) {
        self.label = label
        self.value = value
        self.indicator = indicator
        self.showsGraph = showsGraph
        self.graph = graph
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let indicator {
                    StatusDot(indicator)
                }
                Text(value)
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            if showsGraph {
                graph()
            }
        }
    }
}
