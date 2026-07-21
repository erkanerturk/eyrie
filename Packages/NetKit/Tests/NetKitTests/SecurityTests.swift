import EyrieCore
import Foundation
import Testing
@testable import NetKit

struct ListeningPortsParserTests {
    /// Shaped exactly like `netstat -an -p tcp` on this machine.
    private let sample = """
    Active Internet connections (including servers)
    Proto Recv-Q Send-Q  Local Address          Foreign Address        (state)
    tcp4       0      0  *.7000                 *.*                    LISTEN
    tcp6       0      0  *.7000                 *.*                    LISTEN
    tcp4       0      0  192.168.1.42.5900      *.*                    LISTEN
    tcp4       0      0  127.0.0.1.445          *.*                    LISTEN
    tcp4       0      0  *.63826                *.*                    LISTEN
    tcp4       0      0  192.168.1.42.52341     93.184.216.34.443      ESTABLISHED
    """

    @Test func reportsWellKnownServicesOnce() {
        let services = ListeningPortsParser.services(in: sample)
        #expect(services == [
            ExposedService(port: 5900, name: "Screen Sharing"),
            ExposedService(port: 7000, name: "AirPlay Receiver"),
        ])
    }

    @Test func loopbackOnlyServicesAreNotExposed() {
        // 445 is bound to 127.0.0.1 above — reachable by nobody else.
        #expect(!ListeningPortsParser.services(in: sample).contains { $0.port == 445 })
    }

    /// Link-local is not loopback: every device on the same segment can reach
    /// it, which is exactly what this parser exists to surface.
    @Test func linkLocalServicesAreExposed() {
        let linkLocal = """
        tcp6       0      0  fe80::1cf%en0.5900     *.*                    LISTEN
        """
        #expect(ListeningPortsParser.services(in: linkLocal)
            == [ExposedService(port: 5900, name: "Screen Sharing")])
    }

    @Test func ephemeralPortsAreIgnored() {
        #expect(!ListeningPortsParser.services(in: sample).contains { $0.port == 63826 })
    }

    @Test func nonListeningRowsAreIgnored() {
        let established = """
        tcp4       0      0  192.168.1.42.22        10.0.0.9.51000         ESTABLISHED
        """
        #expect(ListeningPortsParser.services(in: established).isEmpty)
    }

    @Test func garbageInputYieldsNothing() {
        #expect(ListeningPortsParser.services(in: "").isEmpty)
        #expect(ListeningPortsParser.services(in: "not netstat output at all").isEmpty)
    }
}

struct NetworkTrustTests {
    @Test func openNetworkIsUntrusted() {
        let trust = NetworkTrust.evaluate(wifi: stubWiFiDetails(isOpen: true), reachability: .fullInternet)
        #expect(trust == .untrusted)
    }

    @Test func weakEncryptionIsUntrusted() {
        let wifi = stubWiFiDetails(weak: true)
        #expect(NetworkTrust.evaluate(wifi: wifi, reachability: .fullInternet) == .untrusted)
    }

    @Test func captivePortalIsUntrusted() {
        #expect(NetworkTrust.evaluate(wifi: nil, reachability: .captivePortal) == .untrusted)
    }

    @Test func secureWifiAndUnknownStateStayTrusted() {
        #expect(NetworkTrust.evaluate(wifi: stubWiFiDetails(), reachability: .fullInternet) == .trusted)
        // No Wi-Fi details (Ethernet, or Location not granted) is not evidence
        // of danger — it must never raise a false public-network alarm.
        #expect(NetworkTrust.evaluate(wifi: nil, reachability: nil) == .trusted)
    }
}

struct SecurityAdvisorTests {
    private let airplay = [ExposedService(port: 7000, name: "AirPlay Receiver")]

    @Test func healthyTrustedNetworkHasNothingToSay() {
        let findings = SecurityAdvisor.findings(
            trust: .trusted, wifi: stubWiFiDetails(), firewall: .enabled,
            vpn: VPNStatus(), exposedServices: []
        )
        #expect(findings.isEmpty)
    }

    @Test func openNetworkIsReportedAsCritical() {
        let findings = SecurityAdvisor.findings(
            trust: .untrusted, wifi: stubWiFiDetails(isOpen: true), firewall: .enabled,
            vpn: VPNStatus(), exposedServices: []
        )
        #expect(findings.contains { $0.id == "open-network" && $0.tone == .critical })
        // Open beats weak — never both for the same network.
        #expect(!findings.contains { $0.id == "weak-encryption" })
    }

    @Test func firewallToneDependsOnTrust() {
        let trusted = SecurityAdvisor.findings(
            trust: .trusted, wifi: stubWiFiDetails(), firewall: .disabled,
            vpn: VPNStatus(), exposedServices: []
        )
        #expect(trusted.first { $0.id == "firewall-off" }?.tone == .caution)

        let untrusted = SecurityAdvisor.findings(
            trust: .untrusted, wifi: stubWiFiDetails(isOpen: true), firewall: .disabled,
            vpn: VPNStatus(), exposedServices: []
        )
        #expect(untrusted.first { $0.id == "firewall-off" }?.tone == .critical)
    }

    @Test func missingVPNOnlyMattersOnUntrustedNetworks() {
        let trusted = SecurityAdvisor.findings(
            trust: .trusted, wifi: stubWiFiDetails(), firewall: .enabled,
            vpn: VPNStatus(), exposedServices: []
        )
        #expect(!trusted.contains { $0.id == "no-vpn" })

        let untrusted = SecurityAdvisor.findings(
            trust: .untrusted, wifi: stubWiFiDetails(isOpen: true), firewall: .enabled,
            vpn: VPNStatus(), exposedServices: []
        )
        #expect(untrusted.contains { $0.id == "no-vpn" })
    }

    @Test func activeVPNSilencesTheVPNFinding() {
        let vpn = VPNStatus(services: [VPNServiceInfo(serviceID: "a", name: "Work VPN", isConnected: true)])
        let findings = SecurityAdvisor.findings(
            trust: .untrusted, wifi: stubWiFiDetails(isOpen: true), firewall: .enabled,
            vpn: vpn, exposedServices: []
        )
        #expect(!findings.contains { $0.id == "no-vpn" })
    }

    @Test func exposedServicesAreNamedAndEscalateOnUntrusted() {
        let untrusted = SecurityAdvisor.findings(
            trust: .untrusted, wifi: stubWiFiDetails(isOpen: true), firewall: .enabled,
            vpn: VPNStatus(), exposedServices: airplay
        )
        let finding = untrusted.first { $0.id == "exposed-services" }
        #expect(finding?.tone == .critical)
        #expect(finding?.text.contains("AirPlay Receiver") == true)

        let trusted = SecurityAdvisor.findings(
            trust: .trusted, wifi: stubWiFiDetails(), firewall: .enabled,
            vpn: VPNStatus(), exposedServices: airplay
        )
        #expect(trusted.first { $0.id == "exposed-services" }?.tone == .caution)
    }

    @Test func findingsAreOrderedWorstFirst() {
        let findings = SecurityAdvisor.findings(
            trust: .untrusted, wifi: stubWiFiDetails(isOpen: true), firewall: .disabled,
            vpn: VPNStatus(), exposedServices: airplay
        )
        let tones = findings.map(\.tone)
        #expect(tones == tones.sorted(by: >))
        #expect(findings.first?.tone == .critical)
    }

    @Test func unknownFirewallStateIsNotReported() {
        let findings = SecurityAdvisor.findings(
            trust: .trusted, wifi: stubWiFiDetails(), firewall: .unknown,
            vpn: VPNStatus(), exposedServices: []
        )
        #expect(!findings.contains { $0.id == "firewall-off" })
    }
}

struct QualityVerdictTests {
    private func samples(_ latencies: [TimeInterval?]) -> [QualitySample] {
        latencies.enumerated().map {
            QualitySample(id: $0.offset, gatewayLatency: 0.002, internetLatency: $0.element)
        }
    }

    @Test func emptyWindowIsInactive() {
        #expect(QualityVerdict.tone(for: []) == .inactive)
    }

    @Test func fastAndLosslessIsNormal() {
        #expect(QualityVerdict.tone(for: samples([0.010, 0.012, 0.011])) == .normal)
    }

    @Test func moderateLatencyIsCaution() {
        #expect(QualityVerdict.tone(for: samples([0.120, 0.130, 0.125])) == .caution)
    }

    @Test func highLatencyIsCritical() {
        #expect(QualityVerdict.tone(for: samples([0.250, 0.260, 0.255])) == .critical)
    }

    @Test func heavyLossIsCriticalEvenWhenFast() {
        // 3 of 4 lost, the one reply was instant.
        #expect(QualityVerdict.tone(for: samples([0.005, nil, nil, nil])) == .critical)
    }

    @Test func totalLossIsCritical() {
        #expect(QualityVerdict.tone(for: samples([nil, nil, nil])) == .critical)
    }
}
