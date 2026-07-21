import Foundation
import Testing
@testable import TrafficKit

@MainActor
struct DailyUsageTests {
    @Test func firstObservationOnlyBaselines() {
        let store = DailyUsageStore(defaults: temporaryDefaults())
        store.ingest([interface("en0", in: 1000, out: 500)])
        #expect(store.todayBytesIn == 0)
        #expect(store.todayBytesOut == 0)
    }

    @Test func accumulatesDeltasAcrossObservations() {
        let store = DailyUsageStore(defaults: temporaryDefaults())
        store.ingest([interface("en0", in: 1000, out: 500)])
        store.ingest([interface("en0", in: 4000, out: 700)])
        store.ingest([interface("en0", in: 4100, out: 800)])
        #expect(store.todayBytesIn == 3100)
        #expect(store.todayBytesOut == 300)
    }

    @Test func loopbackNeverCounts() {
        let store = DailyUsageStore(defaults: temporaryDefaults())
        store.ingest([interface("lo0", in: 0, out: 0, loopback: true)])
        store.ingest([interface("lo0", in: 9_999_999, out: 9_999_999, loopback: true)])
        #expect(store.todayBytesIn == 0)
    }

    @Test func rebootRegressionRebaselinesWithoutCorruption() {
        let store = DailyUsageStore(defaults: temporaryDefaults())
        store.ingest([interface("en0", in: 10_000, out: 10_000)])
        // Reboot: counters restart near zero — no negative/huge delta.
        store.ingest([interface("en0", in: 100, out: 100)])
        #expect(store.todayBytesIn == 0)
        store.ingest([interface("en0", in: 600, out: 200)])
        #expect(store.todayBytesIn == 500)
        #expect(store.todayBytesOut == 100)
    }

    @Test func vanishingUtunDoesNotAffectOtherInterfaces() {
        let store = DailyUsageStore(defaults: temporaryDefaults())
        store.ingest([
            interface("en0", in: 1000, out: 1000),
            interface("utun4", in: 500, out: 500),
        ])
        // utun4 gone; en0 keeps counting.
        store.ingest([interface("en0", in: 1500, out: 1200)])
        #expect(store.todayBytesIn == 500)
        // utun4 back with reset counters — baseline only, en0 unaffected.
        store.ingest([
            interface("en0", in: 1600, out: 1300),
            interface("utun4", in: 50, out: 50),
        ])
        #expect(store.todayBytesIn == 600)
    }

    @Test func dayRolloverSplitsBuckets() {
        let clock = FakeClock()
        let defaults = temporaryDefaults()
        let store = DailyUsageStore(defaults: defaults, now: { clock.now })
        let firstDay = clock.now

        store.ingest([interface("en0", in: 0, out: 0)])
        store.ingest([interface("en0", in: 1000, out: 100)])
        #expect(store.todayBytesIn == 1000)

        clock.advance(by: 86_400)
        store.ingest([interface("en0", in: 1500, out: 150)])
        #expect(store.todayBytesIn == 500)
        #expect(store.total(for: firstDay)?.bytesIn == 1000)
    }

    @Test func persistsAcrossInstancesAfterFlush() {
        let clock = FakeClock()
        let defaults = temporaryDefaults()
        let first = DailyUsageStore(defaults: defaults, now: { clock.now })
        first.ingest([interface("en0", in: 0, out: 0)])
        first.ingest([interface("en0", in: 2048, out: 512)])
        first.flush()

        let second = DailyUsageStore(defaults: defaults, now: { clock.now })
        #expect(second.todayBytesIn == 2048)
        #expect(second.todayBytesOut == 512)
        // The counter baseline survives too — no double counting.
        second.ingest([interface("en0", in: 2048, out: 512)])
        #expect(second.todayBytesIn == 2048)
    }

    @Test func writesAreThrottledButTimePassingFlushes() {
        let clock = FakeClock()
        let defaults = temporaryDefaults()
        let store = DailyUsageStore(defaults: defaults, now: { clock.now })
        store.ingest([interface("en0", in: 0, out: 0)])
        store.ingest([interface("en0", in: 1000, out: 0)])

        // Within the throttle window nothing new reached disk yet.
        #expect(DailyUsageStore(defaults: defaults, now: { clock.now }).todayBytesIn == 0)

        clock.advance(by: DailyUsageStore.persistInterval + 1)
        store.ingest([interface("en0", in: 1500, out: 0)])
        #expect(DailyUsageStore(defaults: defaults, now: { clock.now }).todayBytesIn == 1500)
    }

    @Test func prunesBeyondRetention() {
        let clock = FakeClock()
        let defaults = temporaryDefaults()
        let store = DailyUsageStore(defaults: defaults, now: { clock.now })
        let firstDay = clock.now

        store.ingest([interface("en0", in: 0, out: 0)])
        for day in 1...(DailyUsageStore.retentionDays + 5) {
            clock.advance(by: 86_400)
            store.ingest([interface("en0", in: UInt64(day) * 100, out: 0)])
        }
        #expect(store.total(for: firstDay) == nil)
        #expect(store.todayBytesIn == 100)
    }
}
