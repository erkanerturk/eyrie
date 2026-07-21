import Testing
@testable import TrafficKit

struct TrafficMathTests {
    @Test func ratesFromConsecutiveFrames() {
        let rates = TrafficMath.rates(
            previous: [process(1, "app", in: 1000, out: 500)],
            current: [process(1, "app", in: 3000, out: 900)],
            elapsed: 2
        )
        #expect(rates.count == 1)
        #expect(rates[0].inPerSecond == 1000)
        #expect(rates[0].outPerSecond == 200)
        #expect(rates[0].bytesIn == 3000)
    }

    @Test func newPidHasTotalsButZeroRate() {
        let rates = TrafficMath.rates(
            previous: [],
            current: [process(7, "fresh", in: 4096, out: 1024)],
            elapsed: 2
        )
        #expect(rates[0].inPerSecond == 0)
        #expect(rates[0].totalBytes == 5120)
    }

    @Test func vanishedPidIsDropped() {
        let rates = TrafficMath.rates(
            previous: [process(1, "gone", in: 10, out: 10), process(2, "stays", in: 5, out: 5)],
            current: [process(2, "stays", in: 6, out: 6)],
            elapsed: 1
        )
        #expect(rates.map(\.pid) == [2])
    }

    @Test func pidReuseWithRegressedCountersZeroesRate() {
        let rates = TrafficMath.rates(
            previous: [process(3, "old", in: 999_999, out: 999_999)],
            current: [process(3, "new", in: 10, out: 10)],
            elapsed: 2
        )
        #expect(rates[0].inPerSecond == 0)
        #expect(rates[0].bytesIn == 10)
    }

    @Test func zeroElapsedGuards() {
        let rates = TrafficMath.rates(
            previous: [process(1, "app", in: 0, out: 0)],
            current: [process(1, "app", in: 100, out: 100)],
            elapsed: 0
        )
        #expect(rates[0].inPerSecond == 0)
    }

    @Test func topConsumersSortByCumulativeTotal() {
        let rates = TrafficMath.rates(
            previous: [],
            current: [
                process(1, "small", in: 10, out: 10),
                process(2, "big", in: 1_000_000, out: 0),
                process(3, "medium", in: 500, out: 500),
            ],
            elapsed: 1
        )
        let top = TrafficMath.topConsumers(rates, count: 2)
        #expect(top.map(\.name) == ["big", "medium"])
        #expect(TrafficMath.topConsumers(rates, count: 0).isEmpty)
    }
}
