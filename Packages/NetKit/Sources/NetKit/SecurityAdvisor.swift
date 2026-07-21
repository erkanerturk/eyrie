import EyrieCore
import Foundation

/// How much the current network deserves the benefit of the doubt.
public enum NetworkTrust: Sendable, Equatable {
    case trusted
    /// Café/hotel shaped: anyone nearby can read or intercept traffic.
    case untrusted

    /// Only definitive signals downgrade trust — an unknown or redacted
    /// security type must never produce a false "public network" alarm.
    public static func evaluate(
        wifi: WiFiDetails?,
        reachability: InternetReachability?
    ) -> NetworkTrust {
        if let wifi, wifi.isOpenNetwork || wifi.isWeakSecurity { return .untrusted }
        if reachability == .captivePortal { return .untrusted }
        return .trusted
    }
}

public struct SecurityFinding: Sendable, Equatable, Identifiable {
    public var id: String
    public var text: String
    public var tone: StatusTone

    public init(id: String, text: String, tone: StatusTone) {
        self.id = id
        self.text = text
        self.tone = tone
    }
}

/// Pure: turns the signals the module already collects into a short, ordered
/// list of things the user can act on. Same data, different urgency depending
/// on whether the network is trusted.
public enum SecurityAdvisor {
    public static func findings(
        trust: NetworkTrust,
        wifi: WiFiDetails?,
        firewall: FirewallState?,
        vpn: VPNStatus?,
        exposedServices: [ExposedService]
    ) -> [SecurityFinding] {
        var findings: [SecurityFinding] = []
        let untrusted = trust == .untrusted

        if let wifi, wifi.isOpenNetwork {
            findings.append(SecurityFinding(
                id: "open-network",
                text: "This network is unencrypted — nearby devices can read your traffic.",
                tone: .critical
            ))
        } else if let wifi, wifi.isWeakSecurity {
            findings.append(SecurityFinding(
                id: "weak-encryption",
                text: "\(wifi.securityLabel) encryption is broken and offers little protection.",
                tone: .critical
            ))
        }

        if firewall == .disabled {
            findings.append(SecurityFinding(
                id: "firewall-off",
                text: untrusted
                    ? "The firewall is off on an untrusted network."
                    : "The firewall is off.",
                tone: untrusted ? .critical : .caution
            ))
        }

        if untrusted, let vpn, !vpn.isActive {
            findings.append(SecurityFinding(
                id: "no-vpn",
                text: "No VPN is active — traffic leaves this Mac in the clear.",
                tone: .caution
            ))
        }

        if !exposedServices.isEmpty {
            let names = exposedServices.map(\.name).joined(separator: ", ")
            findings.append(SecurityFinding(
                id: "exposed-services",
                text: untrusted
                    ? "\(names) reachable from this network."
                    : "\(names) reachable on your local network.",
                tone: untrusted ? .critical : .caution
            ))
        }

        // Worst first, stable within a tone so the list doesn't reshuffle
        // between refreshes.
        return findings.enumerated()
            .sorted { ($0.element.tone, $1.offset) > ($1.element.tone, $0.offset) }
            .map(\.element)
    }
}
