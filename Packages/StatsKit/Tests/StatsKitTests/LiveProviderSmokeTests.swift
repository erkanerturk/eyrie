import Foundation
import Testing
@testable import StatsKit

/// Read-only checks against the real system — nothing to clean up.
struct LiveProviderSmokeTests {
    @Test func sampleReturnsSaneValues() throws {
        let provider = LiveSystemMetricsProvider()
        let sample = try provider.sample()

        #expect(sample.uptime > 0)
        #expect(sample.memoryTotalBytes > 4_000_000_000)
        #expect(sample.memoryUsedBytes > 0)
        #expect(sample.memoryUsedBytes < sample.memoryTotalBytes)
        let ticks = sample.cpu
        #expect(UInt64(ticks.user) + UInt64(ticks.system) + UInt64(ticks.idle) + UInt64(ticks.nice) > 0)
    }

    @Test func twoSamplesYieldPlausibleRates() async throws {
        let provider = LiveSystemMetricsProvider()
        let first = try provider.sample()
        try await Task.sleep(for: .milliseconds(500))
        let second = try provider.sample()

        let snapshot = MetricsMath.snapshot(id: 1, previous: first, current: second, interval: 1)
        let cpu = try #require(snapshot.cpuTotal)
        #expect(cpu >= 0 && cpu <= 1)
        if let down = snapshot.downBytesPerSecond, let up = snapshot.upBytesPerSecond {
            #expect(down >= 0)
            #expect(up >= 0)
        }
    }
}
