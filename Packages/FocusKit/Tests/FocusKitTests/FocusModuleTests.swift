import Foundation
import Testing
import EyrieCore
@testable import FocusKit

@MainActor
struct FocusModuleTests {
    /// Module with an isolated on-disk history and no power assertions, so
    /// tests never touch the real session history or system sleep state.
    private func makeModule(sessionsBeforeLongBreak: Int = 4) -> FocusModule {
        let fileURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString + ".json")
        let module = FocusModule(history: FocusHistoryStore(fileURL: fileURL))
        module.keepAwakeDuringFocus = false
        module.focusMinutes = 25
        module.shortBreakMinutes = 5
        module.longBreakMinutes = 15
        module.sessionsBeforeLongBreak = sessionsBeforeLongBreak
        return module
    }

    @Test func startEntersFocusPhase() {
        let module = makeModule()
        #expect(!module.isActive)

        module.start()
        defer { module.stop() }

        #expect(module.phase == .focus)
        #expect(module.isActive)
        #expect(module.phaseDuration == 25 * 60)
        let end = try! #require(module.phaseEndDate)
        #expect(abs(end.timeIntervalSinceNow - 25 * 60) < 5)
    }

    @Test func skipWalksTheCycleIncludingLongBreak() {
        let module = makeModule(sessionsBeforeLongBreak: 2)
        module.start()
        defer { module.stop() }
        #expect(module.phase == .focus)

        module.skip()
        #expect(module.phase == .shortBreak, "first focus ends in a short break")
        module.skip()
        #expect(module.phase == .focus)
        module.skip()
        #expect(module.phase == .longBreak, "second focus earns the long break")
        #expect(module.cyclePosition == 0, "long break resets the cycle")
        module.skip()
        #expect(module.phase == .focus)
    }

    @Test func skippedFocusIsNotRecordedInHistory() {
        let module = makeModule()
        module.start()
        defer { module.stop() }

        module.skip()
        #expect(module.history.totalSessions == 0)
        #expect(module.completedToday == 0)
    }

    @Test func naturalCompletionRecordsHistoryAndWaitsForUser() {
        let module = makeModule()
        module.start()
        defer { module.stop() }

        module.advance(completedNaturally: true)

        #expect(module.pendingPhase == .shortBreak, "the break must wait for the user, not auto-start")
        #expect(module.phaseEndDate == nil, "no timer may run while pending")
        #expect(module.history.totalSessions == 1)
        #expect(module.completedToday == 1)
        let session = try! #require(module.history.sessions.first)
        #expect(session.duration == 25 * 60)
    }

    @Test func startPendingEntersTheWaitingPhase() {
        let module = makeModule()
        module.start()
        defer { module.stop() }

        module.advance(completedNaturally: true)
        module.startPending()

        #expect(module.phase == .shortBreak)
        #expect(module.pendingPhase == nil)
        let end = try! #require(module.phaseEndDate)
        #expect(abs(end.timeIntervalSinceNow - 5 * 60) < 5)
    }

    @Test func startPendingWithoutPendingPhaseIsHarmless() {
        let module = makeModule()
        module.start()
        defer { module.stop() }

        module.startPending()
        #expect(module.phase == .focus, "startPending must be a no-op while a phase runs")
    }

    @Test func pendingStateHoldsNoKeepAwakeAssertion() {
        let module = makeModule()
        module.keepAwakeDuringFocus = true
        module.start()
        defer { module.stop() }
        #expect(PowerAssertionService.shared.isHoldingAssertion)

        module.advance(completedNaturally: true)
        #expect(!PowerAssertionService.shared.isHoldingAssertion, "pending state must release the assertion")
    }

    @Test func naturalLongBreakWaitsAfterConfiguredSessions() {
        let module = makeModule(sessionsBeforeLongBreak: 2)
        module.start()
        defer { module.stop() }

        module.advance(completedNaturally: true)
        module.startPending() // short break
        module.advance(completedNaturally: true)
        module.startPending() // focus
        module.advance(completedNaturally: true)
        #expect(module.pendingPhase == .longBreak)
        #expect(module.cyclePosition == 0)
    }

    @Test func stopClearsPendingPhase() {
        let module = makeModule()
        module.start()
        module.advance(completedNaturally: true)
        module.stop()

        #expect(module.pendingPhase == nil)
        #expect(module.phase == .idle)
    }

    @Test func breakCompletionRecordsNothing() {
        let module = makeModule()
        module.start()
        defer { module.stop() }

        module.advance(completedNaturally: true) // focus finished (records 1)
        module.startPending()                    // enter short break
        module.advance(completedNaturally: true) // break finished
        #expect(module.pendingPhase == .focus)
        #expect(module.history.totalSessions == 1, "only focus phases are recorded")
    }

    @Test func pauseFreezesAndResumeRestores() {
        let module = makeModule()
        module.start()
        defer { module.stop() }

        module.pause()
        #expect(module.isPaused)
        #expect(module.phaseEndDate == nil)
        let remaining = try! #require(module.pausedRemaining)
        #expect(abs(remaining - 25 * 60) < 5)

        module.resume()
        #expect(!module.isPaused)
        #expect(module.pausedRemaining == nil)
        let end = try! #require(module.phaseEndDate)
        #expect(abs(end.timeIntervalSinceNow - remaining) < 5)
    }

    @Test func pauseReleasesKeepAwakeAssertion() {
        let module = makeModule()
        module.keepAwakeDuringFocus = true
        module.start()
        defer {
            module.stop()
            #expect(!PowerAssertionService.shared.isHoldingAssertion)
        }
        #expect(PowerAssertionService.shared.isHoldingAssertion)

        module.pause()
        #expect(!PowerAssertionService.shared.isHoldingAssertion)

        module.resume()
        #expect(PowerAssertionService.shared.isHoldingAssertion)
    }

    @Test func stopResetsEverything() {
        let module = makeModule()
        module.start()
        module.pause()
        module.stop()

        #expect(module.phase == .idle)
        #expect(!module.isActive)
        #expect(!module.isPaused)
        #expect(module.phaseEndDate == nil)
        #expect(module.pausedRemaining == nil)
    }

    @Test func progressReflectsElapsedTime() {
        let module = makeModule()
        #expect(module.progress(at: .now) == 0, "idle module reports zero progress")

        module.start()
        defer { module.stop() }
        let end = try! #require(module.phaseEndDate)

        #expect(module.progress(at: end.addingTimeInterval(-25 * 60)) == 0)
        #expect(abs(module.progress(at: end.addingTimeInterval(-12.5 * 60)) - 0.5) < 0.01)
        #expect(module.progress(at: end) == 1)
        #expect(module.progress(at: end.addingTimeInterval(60)) == 1, "progress is clamped past the end")
    }
}
