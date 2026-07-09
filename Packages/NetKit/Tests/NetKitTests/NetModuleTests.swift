import Foundation
import Testing
@testable import NetKit

@MainActor
struct NetModuleTests {
    @Test func offlineNeverFetches() {
        let fetcher = ScriptedFetcher()
        let module = NetModule(externalIPFetcher: fetcher)
        module.apply(offlineSnapshot)
        #expect(module.snapshot?.kind == .offline)
        #expect(module.externalIPTask == nil)
        #expect(fetcher.fetchCount == 0)
    }

    @Test func offlineToWifiUpdatesStateAndFetches() async {
        let fetcher = ScriptedFetcher()
        let module = NetModule(externalIPFetcher: fetcher)
        module.apply(offlineSnapshot)
        module.apply(wifiSnapshot())
        await module.externalIPTask?.value
        #expect(module.snapshot?.kind == .wifi)
        #expect(module.snapshot?.displayLocalIP == "192.168.1.42")
        #expect(module.externalIP == "81.2.69.142")
        #expect(fetcher.fetchCount == 1)
    }

    @Test func networkIdentityChangeInvalidatesCacheAndRefetches() async {
        let fetcher = ScriptedFetcher([.success("81.2.69.142"), .success("81.2.69.200")])
        let module = NetModule(externalIPFetcher: fetcher, now: { FakeClock().now })

        module.apply(wifiSnapshot(interface: "en0"))
        await module.externalIPTask?.value
        #expect(module.externalIP == "81.2.69.142")

        module.apply(ethernetSnapshot(interface: "en5"))
        await module.externalIPTask?.value
        #expect(module.externalIP == "81.2.69.200")
        #expect(fetcher.fetchCount == 2)
    }

    @Test func goingOfflineClearsCachedExternalIP() async {
        let module = NetModule(externalIPFetcher: ScriptedFetcher(), now: { FakeClock().now })
        module.apply(wifiSnapshot())
        await module.externalIPTask?.value
        #expect(module.externalIP != nil)

        module.apply(offlineSnapshot)
        #expect(module.externalIP == nil)
        #expect(module.externalIPTask == nil)
    }

    @Test func beginIsIdempotentAndRestartGetsFreshStream() {
        let monitor = ScriptedMonitor()
        let module = NetModule(pathMonitor: monitor, externalIPFetcher: ScriptedFetcher())
        module.begin()
        module.begin()
        #expect(monitor.streamCount <= 1)
        module.end()
        module.begin()
        module.end()
    }

    @Test func shutdownStopsEverything() {
        let module = NetModule(
            pathMonitor: ScriptedMonitor(),
            externalIPFetcher: ScriptedFetcher(hangs: true)
        )
        module.begin()
        module.apply(wifiSnapshot())
        #expect(module.externalIPTask != nil)
        module.shutdown()
        #expect(module.externalIPTask == nil)
        #expect(module.isFetchingExternalIP == false)
    }

    // MARK: - SSID gating

    @Test func deniedAuthorizationNeverExposesSSID() {
        let provider = StubSSIDProvider(status: .denied, ssid: "ShouldNotAppear")
        let module = NetModule(externalIPFetcher: ScriptedFetcher(), ssidProvider: provider)
        defer { module.showSSID = false }

        module.showSSID = true
        module.apply(wifiSnapshot())
        #expect(module.ssid == nil)
        #expect(module.ssidAuthorization == .denied)
    }

    @Test func authorizedWifiShowsSSIDButEthernetDoesNot() {
        let provider = StubSSIDProvider(status: .authorized, ssid: "HomeNet")
        let module = NetModule(externalIPFetcher: ScriptedFetcher(), ssidProvider: provider)
        defer { module.showSSID = false }

        module.showSSID = true
        module.apply(wifiSnapshot())
        #expect(module.ssid == "HomeNet")

        module.apply(ethernetSnapshot())
        #expect(module.ssid == nil)
    }

    @Test func enablingToggleRequestsAuthorizationOnce() {
        let provider = StubSSIDProvider(status: .notDetermined, ssid: "HomeNet")
        let module = NetModule(externalIPFetcher: ScriptedFetcher(), ssidProvider: provider)
        defer { module.showSSID = false }

        module.apply(wifiSnapshot())
        module.showSSID = true
        #expect(provider.requestCount == 1)
        #expect(module.ssid == nil)

        // Authorization arrives later via the delegate callback.
        provider.status = .authorized
        provider.onStatusChange?(.authorized)
        #expect(module.ssidAuthorization == .authorized)
        #expect(module.ssid == "HomeNet")
    }

    @Test func disablingToggleHidesSSID() {
        let provider = StubSSIDProvider(status: .authorized, ssid: "HomeNet")
        let module = NetModule(externalIPFetcher: ScriptedFetcher(), ssidProvider: provider)
        defer { module.showSSID = false }

        module.showSSID = true
        module.apply(wifiSnapshot())
        #expect(module.ssid == "HomeNet")
        module.showSSID = false
        #expect(module.ssid == nil)
    }
}
