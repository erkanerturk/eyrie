import AppKit
import EyrieCore
import SwiftUI

struct NetPanelView: View {
    @Bindable var module: NetModule

    /// Width of the trailing column every detail row ends with — the compact
    /// `GlassIconButton` side, so copy buttons and status dots line up.
    static let trailingSlotWidth: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if module.showStatusBadges {
                // Doubles as the card's header row: connection type first.
                NetStatusBadgeRow(
                    kind: module.snapshot?.kind,
                    vpn: module.vpnStatus,
                    firewall: module.firewallState,
                    reachability: module.reachability,
                    wifi: module.wifiDetails
                )
            }
            if module.showSecurityWarnings, !module.securityFindings.isEmpty {
                securitySection
            }
            CopyableRow(label: "Local IP", value: module.snapshot?.displayLocalIP)
            CopyableRow(label: "External IP", value: module.externalIP,
                        isLoading: module.isFetchingExternalIP)
            if module.showDNS, let config = module.config, !config.dnsServers.isEmpty {
                dnsRow(config)
            }
            if module.showSSID, module.snapshot?.kind == .wifi, let ssid = module.ssid {
                detailRow(label: "Network", value: ssid, monospacedValue: false)
            }
            if module.showWiFiDetails, module.snapshot?.kind == .wifi,
               let details = module.wifiDetails {
                detailRow(label: "Signal", value: signalText(details),
                          tone: WiFiSignalGrade(rssi: details.rssi).tone)
                detailRow(label: "Channel", value: channelText(details))
            }
            if module.showQuality, let kind = module.snapshot?.kind, kind != .offline {
                qualityRow
            }
        }
        .onAppear { module.begin() }
        .onDisappear { module.end() }
    }

    private var securitySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(module.securityFindings) { finding in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    StatusDot(finding.tone)
                        // Nudge the dot onto the first line's optical center.
                        .offset(y: -1)
                    Text(finding.text)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func dnsRow(_ config: SystemNetworkConfig) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            CopyableRow(label: "DNS", value: config.dnsServers.joined(separator: ", "))
            if let classification = DNSClassifier.classify(
                servers: config.dnsServers, router: config.routerAddress
            ) {
                Text(classification.label)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    // Tuck under the value, clear of the copy button.
                    .padding(.trailing, 24)
            }
        }
    }

    /// Latency and loss as one line — the dot carries the verdict, matching
    /// how StatsKit shows memory pressure.
    private var qualityRow: some View {
        HStack(spacing: 6) {
            Text("Quality")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            // Materialized once: `elements` rebuilds the whole 60-sample
            // window, and the tone and the text both need it.
            let samples = module.qualityHistory.elements
            if samples.isEmpty {
                Text("Measuring…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                trailingDot(nil)
            } else {
                Text(qualityText(samples))
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .lineLimit(1)
                trailingDot(QualityVerdict.tone(for: samples))
            }
        }
    }

    /// The dot sits at the trailing edge, centred in a slot as wide as the
    /// compact copy button so dots and copy icons share one column. Rows
    /// without a tone keep the slot empty, so every value ends on the same x.
    private func trailingDot(_ tone: StatusTone?) -> some View {
        Group {
            if let tone {
                StatusDot(tone)
            } else {
                // A real view, not EmptyView — layout drops EmptyView and the
                // frame below would collapse with it.
                Color.clear.frame(width: 6, height: 6)
            }
        }
        .frame(width: NetPanelView.trailingSlotWidth)
    }

    private func qualityText(_ samples: [QualitySample]) -> String {
        let median = PingStats.effectiveMedian(samples)
        let loss = PingStats.lossFraction(samples.map(\.internetLatency)) ?? 0
        let latencyText = median.map { "\(Int(($0 * 1000).rounded())) ms" } ?? "—"
        return "\(latencyText) · \(Int((loss * 100).rounded()))% loss"
    }

    private func detailRow(label: String, value: String, monospacedValue: Bool = true,
                           tone: StatusTone? = nil) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.middle)
                .minimumScaleFactor(0.8)
            trailingDot(tone)
        }
    }

    private func signalText(_ details: WiFiDetails) -> String {
        var parts = ["\(details.rssi) dBm"]
        if details.noise != 0 { parts.append("SNR \(details.snr) dB") }
        parts.append(WiFiSignalGrade(rssi: details.rssi).label)
        return parts.joined(separator: " · ")
    }

    private func channelText(_ details: WiFiDetails) -> String {
        var parts: [String] = []
        if details.channelNumber != 0 { parts.append("\(details.channelNumber)") }
        if !details.band.isEmpty { parts.append(details.band) }
        if !details.channelWidth.isEmpty { parts.append(details.channelWidth) }
        if !details.phyMode.isEmpty { parts.append(details.phyMode) }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }
}

/// Label + monospaced value + always-visible copy button. Copying is the
/// module's core action, so no hover-reveal tricks.
private struct CopyableRow: View {
    var label: String
    var value: String?
    var isLoading = false

    @State private var copied = false

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if isLoading, value == nil {
                ProgressView()
                    .controlSize(.mini)
            }
            Text(value ?? "—")
                .font(.caption.weight(.medium))
                .monospaced()
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            GlassIconButton(symbolName: copied ? "checkmark" : "document.on.document",
                            size: .compact) {
                copy()
            }
            .disabled(value == nil)
            // The glass style pads past the 18 pt icon frame; pinning the
            // button into the shared slot centres it on the status dots
            // instead of letting its padding push it off-column.
            .frame(width: NetPanelView.trailingSlotWidth)
        }
    }

    private func copy() {
        guard let value else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            copied = false
        }
    }
}
