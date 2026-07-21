import Foundation
import Testing
@testable import NetKit

@MainActor
struct NetModuleStatusTests {
    private struct Harness {
        let module: NetModule
        let vpnProvider: StubVPNProvider
        let firewall: ScriptedFirewallProvider
        let captive: ScriptedCaptiveChecker
        let exposed: ScriptedExposedServicesProvider

        /// Awaits whichever status probes are in flight.
        func settle() async {
            await module.firewallTask?.value
            await module.reachabilityTask?.value
            await module.exposedServicesTask?.value
            // The exposed-services scan is kicked off by the firewall result,
            // so it may only exist after the first round settles.
            await module.exposedServicesTask?.value
        }
    }

    private func makeHarness(
        config: SystemNetworkConfig? = SystemNetworkConfig(
            dnsServers: ["192.168.1.1"], routerAddress: "192.168.1.1",
            primaryInterface: "en0", primaryServiceID: "svc"
        ),
        vpn: VPNStatus = VPNStatus(),
        firewall: FirewallState = .enabled,
        captive: InternetReachability = .fullInternet,
        exposed: [ExposedService] = [],
        ssid: StubSSIDProvider? = nil,
        clock: FakeClock = FakeClock()
    ) -> Harness {
        let vpnProvider = StubVPNProvider(vpn)
        let firewallProvider = ScriptedFirewallProvider(firewall)
        let captiveChecker = ScriptedCaptiveChecker(captive)
        let exposedProvider = ScriptedExposedServicesProvider(exposed)
        let module = NetModule(
            pathMonitor: ScriptedMonitor(),
            externalIPFetcher: ScriptedFetcher(),
            ssidProvider: ssid,
            configProvider: StubConfigProvider(config: config),
            vpnProvider: vpnProvider,
            firewallProvider: firewallProvider,
            captiveChecker: captiveChecker,
            exposedServicesProvider: exposedProvider,
            now: { clock.now }
        )
        // Init reads UserDefaults.standard, which sibling tests write through
        // toggle didSets — pin the state this suite depends on.
        module.showStatusBadges = true
        module.showSecurityWarnings = false
        return Harness(module: module, vpnProvider: vpnProvider, firewall: firewallProvider,
                       captive: captiveChecker, exposed: exposedProvider)
    }

    @Test func applyPopulatesConfigVPNAndAsyncChecks() async {
        let harness = makeHarness()
        harness.module.apply(wifiSnapshot())
        #expect(harness.module.config?.routerAddress == "192.168.1.1")
        #expect(harness.vpnProvider.askedInterfaces == ["en0"])

        await harness.settle()
        #expect(harness.module.firewallState == .enabled)
        #expect(harness.module.reachability == .fullInternet)
    }

    /// The bug this replaced: both checks shared one task, so the instant
    /// firewall read waited on the network probe and was lost with it.
    @Test func firewallLandsIndependentlyOfASlowCaptiveCheck() async {
        let harness = makeHarness()
        harness.module.apply(wifiSnapshot())
        await harness.module.firewallTask?.value
        #expect(harness.module.firewallState == .enabled)
    }

    /// Closing the panel must not discard an in-flight probe — that was the
    /// other half of the intermittent badge.
    @Test func endDoesNotCancelStatusProbes() async {
        let harness = makeHarness()
        harness.module.apply(wifiSnapshot())
        harness.module.end()
        await harness.settle()
        #expect(harness.module.firewallState == .enabled)
        #expect(harness.module.reachability == .fullInternet)
    }

    @Test func cachedStatusSurvivesAcrossPanelOpens() async {
        let clock = FakeClock()
        let harness = makeHarness(clock: clock)
        harness.module.apply(wifiSnapshot())
        await harness.settle()
        harness.module.end()
        #expect(harness.firewall.callCount == 1)

        // Reopen inside the TTL: badge is already populated, no new probe.
        clock.advance(by: 10)
        harness.module.apply(wifiSnapshot())
        await harness.settle()
        #expect(harness.module.firewallState == .enabled)
        #expect(harness.firewall.callCount == 1)
    }

    @Test func statusChecksHonorTheirOwnTTL() async {
        let clock = FakeClock()
        let harness = makeHarness(clock: clock)

        harness.module.apply(wifiSnapshot())
        await harness.settle()
        #expect(harness.firewall.callCount == 1)
        #expect(harness.captive.callCount == 1)

        clock.advance(by: 30)
        harness.module.apply(wifiSnapshot())
        await harness.settle()
        #expect(harness.firewall.callCount == 1)

        clock.advance(by: NetModule.statusTTL + 1)
        harness.module.apply(wifiSnapshot())
        await harness.settle()
        #expect(harness.firewall.callCount == 2)
        #expect(harness.captive.callCount == 2)
    }

    @Test func identityChangeForcesReCheckDespiteTTL() async {
        let harness = makeHarness()
        harness.module.apply(wifiSnapshot())
        await harness.settle()
        #expect(harness.firewall.callCount == 1)

        harness.module.apply(ethernetSnapshot())
        await harness.settle()
        #expect(harness.firewall.callCount == 2)
    }

    @Test func goingOfflineClearsStatus() async {
        let harness = makeHarness()
        harness.module.apply(wifiSnapshot())
        await harness.settle()
        #expect(harness.module.config != nil)

        harness.module.apply(offlineSnapshot)
        #expect(harness.module.config == nil)
        #expect(harness.module.vpnStatus == nil)
        #expect(harness.module.reachability == nil)
        #expect(harness.module.wifiDetails == nil)
        #expect(harness.module.securityFindings.isEmpty)
    }

    @Test func allSectionsDisabledSkipsAsyncChecks() async {
        let harness = makeHarness()
        harness.module.showStatusBadges = false
        harness.module.showSecurityWarnings = false

        harness.module.apply(wifiSnapshot())
        await harness.settle()
        #expect(harness.firewall.callCount == 0)
        #expect(harness.module.firewallState == nil)
    }

    @Test func wifiDetailsFollowToggleAndConnectionKind() {
        let stub = StubSSIDProvider(status: .authorized, details: stubWiFiDetails())
        let harness = makeHarness(ssid: stub)
        harness.module.showWiFiDetails = true

        harness.module.apply(wifiSnapshot())
        #expect(harness.module.wifiDetails?.rssi == -52)

        harness.module.apply(ethernetSnapshot())
        #expect(harness.module.wifiDetails == nil)

        harness.module.apply(wifiSnapshot())
        #expect(harness.module.wifiDetails != nil)
        harness.module.showWiFiDetails = false
        #expect(harness.module.wifiDetails == nil)
    }
}

@MainActor
struct NetModuleSecurityTests {
    private func makeModule(
        firewall: FirewallState = .enabled,
        captive: InternetReachability = .fullInternet,
        exposed: ScriptedExposedServicesProvider = ScriptedExposedServicesProvider(),
        wifi: WiFiDetails? = stubWiFiDetails(),
        clock: FakeClock = FakeClock()
    ) -> NetModule {
        let module = NetModule(
            pathMonitor: ScriptedMonitor(),
            externalIPFetcher: ScriptedFetcher(),
            ssidProvider: StubSSIDProvider(status: .authorized, ssid: "Net", details: wifi),
            configProvider: StubConfigProvider(config: SystemNetworkConfig(primaryInterface: "en0")),
            vpnProvider: StubVPNProvider(),
            firewallProvider: ScriptedFirewallProvider(firewall),
            captiveChecker: ScriptedCaptiveChecker(captive),
            exposedServicesProvider: exposed,
            now: { clock.now }
        )
        module.showStatusBadges = true
        module.showSecurityWarnings = true
        return module
    }

    private func settle(_ module: NetModule) async {
        await module.firewallTask?.value
        await module.reachabilityTask?.value
        await module.exposedServicesTask?.value
        await module.exposedServicesTask?.value
    }

    @Test func healthyNetworkProducesNoFindingsAndNoScan() async {
        let exposed = ScriptedExposedServicesProvider([ExposedService(port: 7000, name: "AirPlay Receiver")])
        let module = makeModule(exposed: exposed)
        module.apply(wifiSnapshot())
        await settle(module)

        #expect(module.securityFindings.isEmpty)
        // Cost discipline: nothing is spawned on a trusted, firewalled network.
        #expect(exposed.callCount == 0)
    }

    @Test func openNetworkScansAndReportsFindings() async {
        let exposed = ScriptedExposedServicesProvider([ExposedService(port: 7000, name: "AirPlay Receiver")])
        let module = makeModule(exposed: exposed, wifi: stubWiFiDetails(isOpen: true))
        module.apply(wifiSnapshot())
        await settle(module)

        #expect(exposed.callCount == 1)
        #expect(module.securityFindings.contains { $0.id == "open-network" })
        #expect(module.securityFindings.contains { $0.id == "no-vpn" })
        #expect(module.securityFindings.contains { $0.id == "exposed-services" })
    }

    @Test func disabledFirewallAloneTriggersAScanOnATrustedNetwork() async {
        let exposed = ScriptedExposedServicesProvider([ExposedService(port: 22, name: "Remote Login (SSH)")])
        let module = makeModule(firewall: .disabled, exposed: exposed)
        module.apply(wifiSnapshot())
        await settle(module)

        #expect(exposed.callCount == 1)
        #expect(module.securityFindings.first { $0.id == "firewall-off" }?.tone == .caution)
    }

    @Test func turningWarningsOffClearsFindings() async {
        let module = makeModule(wifi: stubWiFiDetails(isOpen: true))
        module.apply(wifiSnapshot())
        await settle(module)
        #expect(!module.securityFindings.isEmpty)

        module.showSecurityWarnings = false
        #expect(module.securityFindings.isEmpty)
    }

    @Test func wifiSecurityIsReadEvenWithoutTheSignalDetailToggle() async {
        // Security needs the security type; the user opting out of RSSI rows
        // must not blind the open-network check.
        let module = makeModule(wifi: stubWiFiDetails(isOpen: true))
        module.showWiFiDetails = false
        module.apply(wifiSnapshot())
        await settle(module)

        #expect(module.securityFindings.contains { $0.id == "open-network" })
    }
}
