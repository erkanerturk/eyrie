import Foundation
import Testing
@testable import EyrieCore

struct DateTimerRangeTests {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    @Test func futureEndProducesFullRange() {
        let end = now.addingTimeInterval(300)
        let range = Date.timerRange(until: end, now: now)
        #expect(range.lowerBound == now)
        #expect(range.upperBound == end)
    }

    @Test func pastEndCollapsesInsteadOfTrapping() {
        let range = Date.timerRange(until: now.addingTimeInterval(-1), now: now)
        #expect(range.lowerBound == now)
        #expect(range.upperBound == now)
    }

    @Test func equalEndProducesEmptyRange() {
        let range = Date.timerRange(until: now, now: now)
        #expect(range.lowerBound == range.upperBound)
    }
}
