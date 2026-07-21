import Foundation
import Testing
@testable import NetKit

/// Read-only checks against the real system. No external HTTP, no Location.
struct LiveSmokeTests {
    @Test func getifaddrsSeesLoopback() {
        let addresses = LocalAddress.readInterfaceAddresses()
        #expect(addresses.contains { $0.name == "lo0" && $0.address == "127.0.0.1" })
        #expect(addresses.allSatisfy { !$0.address.contains("%") })
    }

    @Test func liveMonitorDeliversFirstSnapshotPromptly() async {
        let stream = LiveNetworkPathMonitor().snapshots()
        let first = await withTaskGroup(of: NetworkSnapshot?.self) { group in
            group.addTask {
                for await snapshot in stream { return snapshot }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(3))
                return nil
            }
            let winner = await group.next() ?? nil
            group.cancelAll()
            return winner
        }
        // Only assert delivery — the machine may legitimately be offline.
        #expect(first != nil)
    }

    @Test func liveConfigProviderReadsDynamicStore() {
        // Machine may be offline (nil is legal); when online the global keys
        // must parse into something coherent.
        if let config = LiveSystemNetworkConfigProvider().currentConfig() {
            #expect(config.primaryInterface == nil || !config.primaryInterface!.isEmpty)
            #expect(config.dnsServers.allSatisfy { !$0.isEmpty })
        }
    }

    @Test func liveVPNProviderGathersWithoutCrashing() {
        let status = LiveVPNStatusProvider().currentStatus(primaryInterface: "en0")
        // Bare utun noise must never read as active without a connected service.
        #expect(status.isFullTunnel == false)
        #expect(status.services.allSatisfy { !$0.serviceID.isEmpty && !$0.name.isEmpty })
    }

    @Test func liveFirewallStateIsReadable() async {
        guard FileManager.default.isExecutableFile(
            atPath: "/usr/libexec/ApplicationFirewall/socketfilterfw"
        ) else { return }
        let state = await LiveFirewallStateProvider().currentState()
        #expect(state != .unknown)
    }

    /// netstat must stay readable without privileges, and the parser must
    /// survive whatever this machine is actually listening on.
    @Test func liveExposedServicesScanIsReadable() async {
        guard FileManager.default.isExecutableFile(atPath: "/usr/sbin/netstat") else { return }
        let services = await LiveExposedServicesProvider().currentServices()
        #expect(services.allSatisfy { $0.port > 0 && !$0.name.isEmpty })
        // Deduplicated: IPv4 and IPv6 listeners on one port are one service.
        #expect(Set(services.map(\.port)).count == services.count)
    }

    /// Permanent regression test for the "unprivileged ICMP SOCK_DGRAM works"
    /// assumption the quality feature stands on. Loopback needs no network.
    @Test func pingServiceGetsLoopbackReply() async {
        let result = await PingService().ping(host: "127.0.0.1", sequence: 9, timeout: 1)
        #expect(result.latency != nil)
        #expect(result.latency.map { $0 < 1 } == true)
    }
}
