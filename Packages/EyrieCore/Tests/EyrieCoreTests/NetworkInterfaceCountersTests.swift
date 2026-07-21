import Testing
import EyrieCore

/// Read-only smoke tests against the real routing socket.
struct NetworkInterfaceCountersTests {
    @Test func seesLoopbackWithProperName() throws {
        let interfaces = try NetworkInterfaceCounters.read()
        let loopback = interfaces.first { $0.name == "lo0" }
        #expect(loopback != nil)
        #expect(loopback?.isLoopback == true)
    }

    @Test func namesAreResolvedNotFallbacks() throws {
        let interfaces = try NetworkInterfaceCounters.read()
        #expect(!interfaces.isEmpty)
        // The sockaddr_dl walk must produce real names, not "if<index>".
        #expect(interfaces.allSatisfy { !$0.name.isEmpty })
        #expect(interfaces.contains { !$0.name.hasPrefix("if") })
    }

    @Test func totalsExcludeLoopbackAndAreStableAcrossReads() throws {
        let first = try NetworkInterfaceCounters.read()
        let second = try NetworkInterfaceCounters.read()
        let firstTotals = NetworkInterfaceCounters.totals(of: first)
        let secondTotals = NetworkInterfaceCounters.totals(of: second)
        // Counters are cumulative since boot — they never regress between
        // two immediate reads.
        #expect(secondTotals.received >= firstTotals.received)
        #expect(secondTotals.sent >= firstTotals.sent)

        let loopback = first.first { $0.isLoopback }
        if let loopback, loopback.bytesIn > 0 {
            let withLoopback = first.reduce(UInt64(0)) { $0 &+ $1.bytesIn }
            #expect(withLoopback > firstTotals.received)
        }
    }
}
