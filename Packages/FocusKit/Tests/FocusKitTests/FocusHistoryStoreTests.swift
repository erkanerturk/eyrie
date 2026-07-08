import Foundation
import Testing
@testable import FocusKit

@MainActor
struct FocusHistoryStoreTests {
    private let fileURL = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString + ".json")

    private func session(endingDaysAgo days: Int, duration: TimeInterval = 1500) -> FocusSession {
        let end = Calendar.current.date(byAdding: .day, value: -days, to: .now)!
        // ISO8601 persistence drops sub-second precision; keep dates round-trippable.
        let wholeSecondEnd = Date(timeIntervalSince1970: end.timeIntervalSince1970.rounded(.down))
        return FocusSession(
            startDate: wholeSecondEnd.addingTimeInterval(-duration),
            endDate: wholeSecondEnd,
            duration: duration
        )
    }

    @Test func recordPersistsAndReloads() {
        let store = FocusHistoryStore(fileURL: fileURL)
        let first = session(endingDaysAgo: 1)
        let second = session(endingDaysAgo: 0)
        store.record(first)
        store.record(second)

        let reloaded = FocusHistoryStore(fileURL: fileURL)
        #expect(reloaded.sessions == [first, second])
    }

    @Test func pruningDropsSessionsOlderThanRetention() {
        let store = FocusHistoryStore(fileURL: fileURL)
        store.record(session(endingDaysAgo: 400))
        let fresh = session(endingDaysAgo: 0)
        store.record(fresh)
        #expect(store.sessions == [fresh])
    }

    @Test func dailyTotalsBucketsByEndDateAndZeroFills() {
        let store = FocusHistoryStore(fileURL: fileURL)
        store.record(session(endingDaysAgo: 0, duration: 1500))
        store.record(session(endingDaysAgo: 0, duration: 300))
        store.record(session(endingDaysAgo: 2, duration: 600))

        let totals = store.dailyTotals(days: 7)
        #expect(totals.count == 7)
        #expect(totals.map(\.day) == totals.map(\.day).sorted())
        #expect(totals.last?.sessionCount == 2)
        #expect(totals.last?.focusSeconds == 1800)
        #expect(totals[4].sessionCount == 1)
        #expect(totals[4].focusSeconds == 600)
        #expect(totals[..<4].allSatisfy { $0.sessionCount == 0 && $0.focusSeconds == 0 })
        #expect(totals[5].sessionCount == 0)
    }

    @Test func completedTodayCountsOnlyToday() {
        let store = FocusHistoryStore(fileURL: fileURL)
        store.record(session(endingDaysAgo: 0))
        store.record(session(endingDaysAgo: 1))
        #expect(store.completedToday == 1)
    }

    @Test func corruptFileLoadsEmpty() throws {
        try Data("not json".utf8).write(to: fileURL)
        let store = FocusHistoryStore(fileURL: fileURL)
        #expect(store.sessions.isEmpty)

        let fresh = session(endingDaysAgo: 0)
        store.record(fresh)
        #expect(FocusHistoryStore(fileURL: fileURL).sessions == [fresh])
    }
}
