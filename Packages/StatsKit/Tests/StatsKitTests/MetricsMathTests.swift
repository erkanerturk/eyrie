import Testing
@testable import StatsKit

private func raw(
    uptime: Double,
    user: UInt32 = 0, system: UInt32 = 0, idle: UInt32 = 0, nice: UInt32 = 0,
    used: UInt64 = 8_000_000_000, total: UInt64 = 16_000_000_000,
    rx: UInt64 = 0, tx: UInt64 = 0
) -> RawMetricsSample {
    RawMetricsSample(
        uptime: uptime,
        cpu: CPUTicks(user: user, system: system, idle: idle, nice: nice),
        memoryUsedBytes: used,
        memoryTotalBytes: total,
        networkBytesReceived: rx,
        networkBytesSent: tx
    )
}

struct MetricsMathTests {
    @Test func memoryPressurePassesThrough() {
        var current = raw(uptime: 10)
        current.memoryPressure = .warning
        let snapshot = MetricsMath.snapshot(id: 0, previous: nil, current: current, interval: 1)
        #expect(snapshot.memoryPressure == .warning)
    }

    @Test func firstSampleHasMemoryButNoRates() {
        let snapshot = MetricsMath.snapshot(id: 0, previous: nil, current: raw(uptime: 10), interval: 1)
        #expect(snapshot.cpuTotal == nil)
        #expect(snapshot.downBytesPerSecond == nil)
        #expect(snapshot.upBytesPerSecond == nil)
        #expect(snapshot.memoryUsedBytes == 8_000_000_000)
        #expect(snapshot.memoryTotalBytes == 16_000_000_000)
    }

    @Test func cpuFractionsFromTickDeltas() {
        let previous = raw(uptime: 10, user: 100, system: 100, idle: 100, nice: 100)
        let current = raw(uptime: 11, user: 130, system: 110, idle: 160, nice: 100)
        let snapshot = MetricsMath.snapshot(id: 1, previous: previous, current: current, interval: 1)
        // Δuser 30, Δsystem 10, Δidle 60, Δnice 0 → busy 40 / total 100
        #expect(snapshot.cpuTotal == 0.4)
        #expect(snapshot.cpuUser == 0.3)
        #expect(snapshot.cpuSystem == 0.1)
    }

    @Test func cpuTicksSurviveUInt32Wrap() {
        let previous = raw(uptime: 10, user: UInt32.max - 10, idle: 0)
        let current = raw(uptime: 11, user: 20, idle: 69)
        let snapshot = MetricsMath.snapshot(id: 1, previous: previous, current: current, interval: 1)
        // Δuser wraps to 31, Δidle 69 → busy 31 / total 100
        #expect(snapshot.cpuTotal == 0.31)
    }

    @Test func zeroTotalTicksGivesNilCPU() {
        let previous = raw(uptime: 10, user: 5)
        let current = raw(uptime: 11, user: 5)
        let snapshot = MetricsMath.snapshot(id: 1, previous: previous, current: current, interval: 1)
        #expect(snapshot.cpuTotal == nil)
    }

    @Test func networkRateFromByteDeltas() {
        let previous = raw(uptime: 10, idle: 1, rx: 5_000_000, tx: 1_000_000)
        let current = raw(uptime: 11, idle: 2, rx: 6_000_000, tx: 1_250_000)
        let snapshot = MetricsMath.snapshot(id: 1, previous: previous, current: current, interval: 1)
        #expect(snapshot.downBytesPerSecond == 1_000_000)
        #expect(snapshot.upBytesPerSecond == 250_000)
    }

    @Test func networkCounterRegressionGivesNilRates() {
        // An interface vanishing (e.g. VPN) shrinks the aggregate counter.
        let previous = raw(uptime: 10, idle: 1, rx: 9_000_000, tx: 500_000)
        let current = raw(uptime: 11, idle: 2, rx: 6_000_000, tx: 600_000)
        let snapshot = MetricsMath.snapshot(id: 1, previous: previous, current: current, interval: 1)
        #expect(snapshot.downBytesPerSecond == nil)
        #expect(snapshot.upBytesPerSecond == nil)
    }

    @Test func longGapDropsRates() {
        // Elapsed 10 s at 1 s interval → slept; rates must not be averaged.
        let previous = raw(uptime: 10, user: 100, idle: 100, rx: 1_000)
        let current = raw(uptime: 20, user: 200, idle: 200, rx: 2_000)
        let snapshot = MetricsMath.snapshot(id: 1, previous: previous, current: current, interval: 1)
        #expect(snapshot.cpuTotal == nil)
        #expect(snapshot.downBytesPerSecond == nil)
        #expect(snapshot.memoryUsedBytes == 8_000_000_000)
    }

    @Test func tinyElapsedDropsRates() {
        let previous = raw(uptime: 10, user: 100, idle: 100)
        let current = raw(uptime: 10.01, user: 101, idle: 101)
        let snapshot = MetricsMath.snapshot(id: 1, previous: previous, current: current, interval: 1)
        #expect(snapshot.cpuTotal == nil)
    }
}
