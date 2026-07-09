import Foundation
import Testing
@testable import NetKit

struct IPValidatorTests {
    @Test func acceptsPlainIPv4() {
        #expect(IPValidator.normalize("81.2.69.142") == "81.2.69.142")
    }

    @Test func trimsSurroundingWhitespace() {
        #expect(IPValidator.normalize("81.2.69.142\n") == "81.2.69.142")
        #expect(IPValidator.normalize("  2a02:8109::1 ") == "2a02:8109::1")
    }

    @Test func acceptsIPv6() {
        #expect(IPValidator.normalize("2a02:8109:9c40:1234::7") == "2a02:8109:9c40:1234::7")
    }

    @Test func rejectsNonAddresses() {
        #expect(IPValidator.normalize("") == nil)
        #expect(IPValidator.normalize("<html><body>Login</body></html>") == nil)
        #expect(IPValidator.normalize("81.2.69") == nil)
        #expect(IPValidator.normalize("not an ip") == nil)
    }
}

@MainActor
struct ExternalIPCacheTests {
    @Test func fetchesOnceWithinTTLAcrossPanelReopens() async {
        let fetcher = ScriptedFetcher([.success("81.2.69.142"), .success("81.2.69.200")])
        let clock = FakeClock()
        let module = NetModule(externalIPFetcher: fetcher, now: { clock.now })

        module.apply(wifiSnapshot())
        await module.externalIPTask?.value
        #expect(module.externalIP == "81.2.69.142")
        #expect(fetcher.fetchCount == 1)

        // Panel close + reopen inside the TTL: cached value, zero traffic.
        module.end()
        module.apply(wifiSnapshot())
        await module.externalIPTask?.value
        #expect(module.externalIP == "81.2.69.142")
        #expect(fetcher.fetchCount == 1)
    }

    @Test func refetchesAfterTTLExpiry() async {
        let fetcher = ScriptedFetcher([.success("81.2.69.142"), .success("81.2.69.200")])
        let clock = FakeClock()
        let module = NetModule(externalIPFetcher: fetcher, now: { clock.now })

        module.apply(wifiSnapshot())
        await module.externalIPTask?.value
        clock.advance(by: 301)
        module.apply(wifiSnapshot())
        await module.externalIPTask?.value
        #expect(module.externalIP == "81.2.69.200")
        #expect(fetcher.fetchCount == 2)
    }

    @Test func failureDoesNotPoisonTTL() async {
        let fetcher = ScriptedFetcher([.failure(URLError(.timedOut)), .success("81.2.69.142")])
        let module = NetModule(externalIPFetcher: fetcher, now: { FakeClock().now })

        module.apply(wifiSnapshot())
        await module.externalIPTask?.value
        #expect(module.externalIP == nil)
        #expect(module.isFetchingExternalIP == false)

        // Next snapshot retries immediately — the failure stamped no timestamp.
        module.apply(wifiSnapshot())
        await module.externalIPTask?.value
        #expect(module.externalIP == "81.2.69.142")
        #expect(fetcher.fetchCount == 2)
    }

    @Test func endCancelsInFlightFetch() async {
        let fetcher = ScriptedFetcher(hangs: true)
        let module = NetModule(externalIPFetcher: fetcher, now: { FakeClock().now })

        module.apply(wifiSnapshot())
        let task = module.externalIPTask
        #expect(task != nil)
        module.end()
        await task?.value
        #expect(module.externalIPTask == nil)
        #expect(module.externalIP == nil)
        #expect(module.isFetchingExternalIP == false)
    }
}
