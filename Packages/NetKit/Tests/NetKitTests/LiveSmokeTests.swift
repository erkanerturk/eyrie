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
}
