import Foundation
import Testing
@testable import NetKit

struct VPNInterpreterTests {
    private func record(
        id: String = "svc-1",
        name: String = "Work VPN",
        type: String = "VPN",
        hasState: Bool = false,
        status: VPNConnectionStatus = .disconnected
    ) -> VPNServiceRecord {
        VPNServiceRecord(serviceID: id, name: name, interfaceType: type,
                         hasActiveState: hasState, connectionStatus: status)
    }

    @Test func disconnectedServiceOnRegularInterfaceIsInactive() {
        let status = VPNStateInterpreter.status(records: [record()], primaryInterface: "en0")
        #expect(!status.isActive)
        #expect(!status.isFullTunnel)
        #expect(status.services.count == 1)
    }

    @Test func connectedServiceWithTunnelPrimaryIsFullTunnel() {
        let status = VPNStateInterpreter.status(
            records: [record(status: .connected)],
            primaryInterface: "utun6"
        )
        #expect(status.isActive)
        #expect(status.isFullTunnel)
        #expect(status.connectedNames == ["Work VPN"])
    }

    @Test func detectionIsVendorAgnosticAcrossServiceTypes() {
        // Nothing keys off a particular product: an IPSec service configured
        // in System Settings must read exactly like a NetworkExtension one.
        for type in ["VPN", "IPSec", "PPP"] {
            let status = VPNStateInterpreter.status(
                records: [record(name: "Some \(type)", type: type, status: .connected)],
                primaryInterface: "en0"
            )
            #expect(status.isActive)
            #expect(status.connectedNames == ["Some \(type)"])
        }
    }

    @Test func splitTunnelIsActiveButNotFullTunnel() {
        // Connected service, but the default route stays on en0.
        let status = VPNStateInterpreter.status(
            records: [record(status: .connected)],
            primaryInterface: "en0"
        )
        #expect(status.isActive)
        #expect(!status.isFullTunnel)
    }

    @Test func activeStateCountsAsConnectedEvenWithoutConnectionStatus() {
        // NE-based VPNs sometimes report .invalid via SCNetworkConnection but
        // still publish State: addresses.
        let status = VPNStateInterpreter.status(
            records: [record(hasState: true, status: .invalid)],
            primaryInterface: "en0"
        )
        #expect(status.isActive)
    }

    @Test func tunnelPrimaryAloneIsFullTunnel() {
        // Full-tunnel VPN with no SC-visible service (pure NE tunnel).
        let status = VPNStateInterpreter.status(records: [], primaryInterface: "utun4")
        #expect(status.isActive)
        #expect(status.isFullTunnel)
        #expect(status.connectedNames.isEmpty)
    }

    @Test func nilPrimaryInterfaceNeverFullTunnel() {
        let status = VPNStateInterpreter.status(records: [], primaryInterface: nil)
        #expect(!status.isActive)
    }
}

struct DNSClassifierTests {
    @Test func routerAsOnlyResolverIsRouterDefault() {
        let result = DNSClassifier.classify(servers: ["192.168.1.1"], router: "192.168.1.1")
        #expect(result == .routerDefault)
    }

    @Test func knownPublicResolverPairIsNamed() {
        let result = DNSClassifier.classify(servers: ["1.1.1.1", "1.0.0.1"], router: "192.168.1.1")
        #expect(result == .publicResolver("Cloudflare"))
    }

    @Test func mixedProvidersAreCustom() {
        let result = DNSClassifier.classify(servers: ["1.1.1.1", "8.8.8.8"], router: nil)
        #expect(result == .custom)
    }

    @Test func unknownServerIsCustom() {
        let result = DNSClassifier.classify(servers: ["10.0.0.53"], router: "10.0.0.1")
        #expect(result == .custom)
    }

    @Test func knownResolverMixedWithUnknownIsCustom() {
        let result = DNSClassifier.classify(servers: ["1.1.1.1", "10.0.0.53"], router: nil)
        #expect(result == .custom)
    }

    @Test func emptyServersClassifyAsNil() {
        #expect(DNSClassifier.classify(servers: [], router: "192.168.1.1") == nil)
    }
}

struct FirewallParserTests {
    @Test func stateZeroIsDisabled() {
        let state = FirewallOutputParser.parse(status: 0, output: "Firewall is disabled. (State = 0)\n")
        #expect(state == .disabled)
    }

    @Test func stateOneIsEnabled() {
        let state = FirewallOutputParser.parse(status: 0, output: "Firewall is enabled. (State = 1)\n")
        #expect(state == .enabled)
    }

    @Test func stateTwoIsBlockAll() {
        let state = FirewallOutputParser.parse(status: 0, output: "Firewall is set to block all non-essential incoming connections. (State = 2)\n")
        #expect(state == .blockAll)
    }

    @Test func garbageOutputIsUnknown() {
        #expect(FirewallOutputParser.parse(status: 0, output: "unexpected") == .unknown)
    }

    @Test func nonZeroExitIsUnknownEvenWithParsableOutput() {
        #expect(FirewallOutputParser.parse(status: 1, output: "(State = 1)") == .unknown)
    }
}

struct CaptiveClassifierTests {
    @Test func successBodyIsFullInternet() {
        let result = CaptiveResponseClassifier.classify(
            statusCode: 200,
            body: "<HTML><HEAD><TITLE>Success</TITLE></HEAD><BODY>Success</BODY></HTML>"
        )
        #expect(result == .fullInternet)
    }

    @Test func redirectIsCaptivePortal() {
        #expect(CaptiveResponseClassifier.classify(statusCode: 302, body: nil) == .captivePortal)
    }

    @Test func portalLoginPageIsCaptivePortal() {
        let result = CaptiveResponseClassifier.classify(
            statusCode: 200,
            body: "<html><body>Hotel guest login</body></html>"
        )
        #expect(result == .captivePortal)
    }

    @Test func noResponseIsNoInternet() {
        #expect(CaptiveResponseClassifier.classify(statusCode: nil, body: nil) == .noInternet)
    }
}

struct WiFiSignalGradeTests {
    @Test func gradeBoundaries() {
        #expect(WiFiSignalGrade(rssi: -40) == .excellent)
        #expect(WiFiSignalGrade(rssi: -55) == .excellent)
        #expect(WiFiSignalGrade(rssi: -60) == .good)
        #expect(WiFiSignalGrade(rssi: -70) == .fair)
        #expect(WiFiSignalGrade(rssi: -80) == .weak)
    }
}
