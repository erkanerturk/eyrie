import EyrieCore
import SwiftUI

/// The card's header: connection type first, then VPN / firewall / warnings.
/// It replaces a separate title row, so the type badge also carries the
/// online state through its tone. Unknown or nil states render nothing, and
/// badges wrap instead of clipping on the fixed 340 pt panel.
struct NetStatusBadgeRow: View {
    var kind: ConnectionKind?
    var vpn: VPNStatus?
    var firewall: FirewallState?
    var reachability: InternetReachability?
    var wifi: WiFiDetails?

    var body: some View {
        FlowLayout(spacing: 5, lineSpacing: 4) {
            ForEach(badges) { badge in
                HStack(spacing: 3) {
                    Image(systemName: badge.symbolName)
                        .font(.system(size: 9, weight: .semibold))
                    Text(badge.text)
                        .font(.caption2.weight(.medium))
                        .lineLimit(1)
                }
                .foregroundStyle(badge.tone.color)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(badge.tone.color.opacity(0.12), in: .capsule)
            }
        }
    }

    private var badges: [Badge] {
        var result: [Badge] = [connectionBadge]
        if let vpn, vpn.isActive {
            let names = vpn.connectedNames
            result.append(Badge(
                id: "vpn",
                symbolName: "lock.shield.fill",
                text: names.count == 1 ? names[0] : "VPN",
                tone: .normal
            ))
        }
        switch firewall {
        case .enabled:
            result.append(Badge(id: "firewall", symbolName: "shield.lefthalf.filled",
                                text: "Firewall", tone: .normal))
        case .blockAll:
            result.append(Badge(id: "firewall", symbolName: "shield.fill",
                                text: "Block all", tone: .normal))
        case .disabled:
            result.append(Badge(id: "firewall", symbolName: "shield.slash",
                                text: "Firewall off", tone: .caution))
        case .unknown, nil:
            break
        }
        if wifi?.isOpenNetwork == true {
            result.append(Badge(id: "open-wifi", symbolName: "exclamationmark.triangle.fill",
                                text: "Open Wi-Fi", tone: .caution))
        } else if wifi?.isWeakSecurity == true {
            result.append(Badge(id: "weak-wifi", symbolName: "exclamationmark.triangle.fill",
                                text: "Weak security", tone: .caution))
        }
        switch reachability {
        case .captivePortal:
            result.append(Badge(id: "captive", symbolName: "wifi.exclamationmark",
                                text: "Captive portal", tone: .caution))
        case .noInternet:
            result.append(Badge(id: "no-internet", symbolName: "globe.badge.chevron.backward",
                                text: "No internet", tone: .critical))
        case .fullInternet, nil:
            break
        }
        return result
    }

    private var connectionBadge: Badge {
        guard let kind else {
            return Badge(id: "kind", symbolName: "wifi", text: "Checking…", tone: .inactive)
        }
        return Badge(
            id: "kind",
            symbolName: kind.symbolName,
            text: kind.label,
            tone: kind == .offline ? .inactive : .normal
        )
    }

    private struct Badge: Identifiable {
        let id: String
        let symbolName: String
        let text: String
        let tone: StatusTone
    }
}
