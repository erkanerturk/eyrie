import EyrieCore
import Foundation
import Testing
@testable import TrafficKit

/// Read-only checks against the real system.
struct LiveSmokeTests {
    /// Format-drift canary: a real sample must parse into at least one
    /// process. If Apple changes nettop's CSV shape, this fires first.
    @Test func liveSamplerReturnsProcesses() async throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/nettop") else { return }
        let sample = await LiveNettopSampler().sample()
        let processes = try #require(sample)
        #expect(!processes.isEmpty)
        #expect(processes.allSatisfy { $0.pid >= 0 && !$0.name.isEmpty })
    }

    /// `-n` is load-bearing: without it nettop spends a fixed ~5 s resolving
    /// names (measured 5.04 s → 0.01 s), which would make per-tick sampling
    /// impossible. Guard the assumption rather than rediscovering it.
    @Test func samplingStaysFastEnoughForPerTickUse() async throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/nettop") else { return }
        let started = Date()
        _ = await LiveNettopSampler().sample()
        #expect(Date().timeIntervalSince(started) < 2)
    }
}
