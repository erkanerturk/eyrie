import EyrieCore
import SwiftUI

struct TrafficPanelView: View {
    @Bindable var module: TrafficModule

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if module.showPerApp {
                perAppSection
                Divider()
            }
            totalRow(label: "Since boot", received: module.sessionReceived, sent: module.sessionSent)
            totalRow(label: "Today", received: module.usageStore.todayBytesIn,
                     sent: module.usageStore.todayBytesOut)
        }
        .onAppear { module.begin() }
        .onDisappear { module.end() }
    }

    @ViewBuilder
    private var perAppSection: some View {
        if let rows = module.topConsumers {
            VStack(alignment: .leading, spacing: 5) {
                // Already sorted, capped and name-resolved by the module.
                ForEach(rows) { row in
                    appRow(row)
                }
            }
        } else if module.perAppUnavailable {
            Text("Per-app traffic is unavailable.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text("Measuring…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func appRow(_ row: ProcessTrafficRate) -> some View {
        HStack(spacing: 6) {
            Text(row.displayName)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            if row.inPerSecond + row.outPerSecond >= 1024 {
                Text(rateText(row))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Text(Int64(clamping: row.totalBytes).formatted(.byteCount(style: .file)))
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    private func rateText(_ row: ProcessTrafficRate) -> String {
        "↓ \(Self.rate(row.inPerSecond)) ↑ \(Self.rate(row.outPerSecond))"
    }

    private func totalRow(label: String, received: UInt64?, sent: UInt64?) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(totalText(received: received, sent: sent))
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    private func totalText(received: UInt64?, sent: UInt64?) -> String {
        guard let received, let sent else { return "—" }
        let down = Int64(clamping: received).formatted(.byteCount(style: .file))
        let up = Int64(clamping: sent).formatted(.byteCount(style: .file))
        return "↓ \(down)  ↑ \(up)"
    }

    /// `Int64(Double)` traps on NaN, infinity and anything outside Int64's
    /// range, so bound the value first — the totals above use
    /// `Int64(clamping:)` for the same reason.
    private static func rate(_ bytesPerSecond: Double) -> String {
        let bounded = bytesPerSecond.isFinite ? min(max(bytesPerSecond, 0), 1e18) : 0
        return Int64(bounded).formatted(.byteCount(style: .memory)) + "/s"
    }
}
