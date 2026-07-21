import EyrieCore
import Foundation
import Testing
@testable import TrafficKit

@MainActor
struct TrafficModuleTests {
    private func makeModule(
        sampler: ScriptedSampler = ScriptedSampler(),
        counters: [InterfaceCounters] = [interface("en0", in: 1000, out: 500)],
        clock: FakeClock = FakeClock()
    ) -> TrafficModule {
        let defaults = temporaryDefaults()
        let module = TrafficModule(
            sampler: sampler,
            readCounters: { counters },
            usageStore: DailyUsageStore(defaults: defaults, now: { clock.now }),
            defaults: defaults,
            now: { clock.now }
        )
        // Suite-local defaults, so these writes never reach the real app.
        module.showPerApp = true
        module.topCount = 5
        return module
    }

    @Test func firstFrameShowsTotalsSecondFrameShowsRates() {
        let clock = FakeClock()
        let module = makeModule(clock: clock)
        module.applyFrame([process(10, "app", in: 1000, out: 0)])
        #expect(module.topConsumers?.count == 1)
        #expect(module.topConsumers?[0].inPerSecond == 0)
        #expect(module.topConsumers?[0].bytesIn == 1000)

        clock.advance(by: 2)
        module.applyFrame([process(10, "app", in: 5000, out: 0)])
        #expect(module.topConsumers?[0].inPerSecond == 2000)
    }

    @Test func nilOrEmptySampleMarksUnavailable() {
        let module = makeModule()
        module.applyFrame([process(1, "x", in: 1, out: 1)])
        module.applyFrame(nil)
        #expect(module.topConsumers == nil)
        #expect(module.perAppUnavailable)

        module.applyFrame([process(1, "x", in: 2, out: 2)])
        #expect(!module.perAppUnavailable)
        module.applyFrame([])
        #expect(module.perAppUnavailable)
    }

    @Test func topConsumersAreSortedAndCappedByTheModule() {
        let module = makeModule()
        module.topCount = 2
        module.applyFrame([
            process(1, "small", in: 10, out: 10),
            process(2, "big", in: 1_000_000, out: 0),
            process(3, "medium", in: 500, out: 500),
        ])
        #expect(module.topConsumers?.map(\.name) == ["big", "medium"])
        // Display names are resolved up front, never in the view body.
        #expect(module.topConsumers?.allSatisfy { !$0.displayName.isEmpty } == true)
    }

    @Test func changingTopCountRecomputesWithoutANewSample() {
        let sampler = ScriptedSampler()
        let module = makeModule(sampler: sampler)
        module.applyFrame([
            process(1, "a", in: 30, out: 0),
            process(2, "b", in: 20, out: 0),
            process(3, "c", in: 10, out: 0),
        ])
        module.topCount = 2
        #expect(module.topConsumers?.count == 2)
        #expect(sampler.sampleCount == 0)
    }

    @Test func countersTickUpdatesSessionTotalsAndDailyStore() {
        let module = makeModule(counters: [
            interface("en0", in: 4000, out: 2000),
            interface("lo0", in: 999, out: 999, loopback: true),
        ])
        module.readInterfaceCounters()
        #expect(module.sessionReceived == 4000)
        #expect(module.sessionSent == 2000)
        // First ingest only baselines the daily store.
        #expect(module.usageStore.todayBytesIn == 0)
    }

    @Test func tickSamplesOnlyWhenPerAppIsOn() async {
        let sampler = ScriptedSampler([[process(1, "a", in: 10, out: 10)]])
        let module = makeModule(sampler: sampler)
        module.showPerApp = false

        await module.tick()
        #expect(sampler.sampleCount == 0)
        #expect(module.sessionReceived != nil)  // counters still read

        module.showPerApp = true
        await module.tick()
        #expect(sampler.sampleCount == 1)
        #expect(module.topConsumers?.count == 1)
    }

    @Test func beginIsIdempotentAndEndStops() async {
        let sampler = ScriptedSampler([[process(1, "a", in: 10, out: 10)]])
        let module = makeModule(sampler: sampler)
        module.begin()
        module.begin()
        for _ in 0..<50 where module.topConsumers == nil {
            await Task.yield()
        }
        #expect(module.topConsumers != nil)
        let afterBegin = sampler.sampleCount

        module.end()
        // Give a cancelled loop a chance to (not) fire again.
        for _ in 0..<20 { await Task.yield() }
        #expect(sampler.sampleCount <= afterBegin + 1)
    }

    @Test func disablingPerAppClearsRows() {
        let module = makeModule()
        module.applyFrame([process(1, "a", in: 10, out: 10)])
        module.showPerApp = false
        #expect(module.topConsumers == nil)
        #expect(!module.perAppUnavailable)
    }

    @Test func backgroundIntervalPersistsAndIsBounded() {
        let module = makeModule()
        module.backgroundIntervalMinutes = 5
        #expect(module.backgroundIntervalMinutes == 5)
        #expect(TrafficModule.backgroundIntervalChoices == [5, 10, 20])
    }

    /// A module the user switched off is still instantiated by the registry —
    /// it must not keep reading counters in the background.
    @Test func aDisabledModuleRunsNoBackgroundWork() async {
        let reads = CallCounter()
        let module = makeBackgroundModule(reads: reads)
        module.setModuleEnabled(false)
        module.backgroundTracking = true
        for _ in 0..<20 { await Task.yield() }
        #expect(reads.value == 0)

        // Re-enabling brings the loop back with its immediate baseline read.
        module.setModuleEnabled(true)
        for _ in 0..<50 where reads.value == 0 {
            await Task.yield()
        }
        #expect(reads.value >= 1)
    }

    /// Init cannot know the module's enabled state yet, so it must not start
    /// the loop at all — the registry's `setModuleEnabled(_:)` does. Before,
    /// init started it optimistically and the task's unguarded baseline read
    /// ran even though the registry cancelled it on the very next line.
    @Test func initStartsNoBackgroundWorkBeforeTheRegistryPinsTheState() async {
        let reads = CallCounter()
        let defaults = temporaryDefaults()
        defaults.set(true, forKey: "traffic.backgroundTracking")
        let module = makeBackgroundModule(reads: reads, defaults: defaults)
        #expect(module.backgroundTracking)

        for _ in 0..<20 { await Task.yield() }
        #expect(reads.value == 0)

        // …and the registry switching it on is what actually starts it.
        module.setModuleEnabled(true)
        for _ in 0..<50 where reads.value == 0 {
            await Task.yield()
        }
        #expect(reads.value >= 1)
    }

    private func makeBackgroundModule(
        reads: CallCounter, defaults: UserDefaults = temporaryDefaults()
    ) -> TrafficModule {
        TrafficModule(
            sampler: ScriptedSampler(),
            readCounters: { reads.increment(); return [interface("en0", in: 1, out: 1)] },
            usageStore: DailyUsageStore(defaults: defaults),
            defaults: defaults
        )
    }
}
