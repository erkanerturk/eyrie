import Foundation
import Testing
@testable import StatsKit

/// Replays a fixed list of samples; thread-safe for strict concurrency.
private final class ScriptedProvider: SystemMetricsProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [RawMetricsSample]

    init(_ samples: [RawMetricsSample]) {
        queue = samples
    }

    func sample() throws -> RawMetricsSample {
        lock.lock()
        defer { lock.unlock() }
        guard !queue.isEmpty else { throw CocoaError(.fileNoSuchFile) }
        return queue.removeFirst()
    }
}

private func sample(uptime: Double, user: UInt32, idle: UInt32, rx: UInt64) -> RawMetricsSample {
    RawMetricsSample(
        uptime: uptime,
        cpu: CPUTicks(user: user, system: 0, idle: idle, nice: 0),
        memoryUsedBytes: 4_000_000_000,
        memoryTotalBytes: 16_000_000_000,
        networkBytesReceived: rx,
        networkBytesSent: 0
    )
}

@MainActor
struct StatsModuleTests {
    @Test func twoTicksProduceRatesAndHistory() {
        let module = StatsModule(provider: ScriptedProvider([
            sample(uptime: 100, user: 10, idle: 90, rx: 1_000),
            sample(uptime: 101, user: 40, idle: 160, rx: 501_000),
        ]))
        module.tick()
        #expect(module.latest?.cpuTotal == nil)
        module.tick()
        #expect(module.history.count == 2)
        #expect(module.latest?.cpuTotal == 0.3)
        #expect(module.latest?.downBytesPerSecond == 500_000)
    }

    @Test func beginSamplingIsIdempotent() {
        let module = StatsModule(provider: ScriptedProvider([
            sample(uptime: 100, user: 10, idle: 90, rx: 0),
            sample(uptime: 101, user: 20, idle: 180, rx: 0),
        ]))
        module.beginSampling()
        module.beginSampling()
        // Only the first call runs its immediate tick; the second is a no-op.
        #expect(module.history.count == 1)
        module.endSampling()
    }

    @Test func endSamplingClearsBaseline() {
        let module = StatsModule(provider: ScriptedProvider([
            sample(uptime: 100, user: 10, idle: 90, rx: 1_000),
            sample(uptime: 101, user: 40, idle: 160, rx: 2_000),
            sample(uptime: 102, user: 70, idle: 230, rx: 3_000),
        ]))
        module.tick()
        module.tick()
        #expect(module.latest?.cpuTotal != nil)

        module.endSampling()
        module.tick()
        // First tick after a restart must be baseline-only again.
        #expect(module.latest?.cpuTotal == nil)
        #expect(module.history.count == 3)
    }

    @Test func providerFailureKeepsLastSnapshot() {
        let module = StatsModule(provider: ScriptedProvider([
            sample(uptime: 100, user: 10, idle: 90, rx: 0),
        ]))
        module.tick()
        let before = module.latest
        module.tick() // provider queue is empty → throws → snapshot unchanged
        #expect(module.latest == before)
        #expect(module.history.count == 1)
    }
}
