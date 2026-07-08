import SwiftUI
import EyrieCore

public enum FocusPhase: String, Sendable {
    case idle
    case focus
    case shortBreak
    case longBreak

    var label: String {
        switch self {
        case .idle: "Idle"
        case .focus: "Focus"
        case .shortBreak: "Short Break"
        case .longBreak: "Long Break"
        }
    }

    var isBreak: Bool { self == .shortBreak || self == .longBreak }
}

/// Pomodoro state machine (Flow core): focus → short break, with a long break
/// after every N focus sessions. When a phase finishes naturally the machine
/// waits in a "pending" state until the user starts the next phase; only an
/// explicit skip jumps straight in.
@MainActor
@Observable
public final class FocusModule: EyrieModule {
    public let id = "focus"
    public let name = "Focus"
    public var symbolName: String { isActive ? "timer.circle.fill" : "timer" }

    public private(set) var phase: FocusPhase = .idle
    public private(set) var phaseEndDate: Date?
    public private(set) var phaseDuration: TimeInterval = 0
    public private(set) var isPaused = false
    /// Remaining seconds captured when pausing.
    public private(set) var pausedRemaining: TimeInterval?
    /// Focus sessions finished in the current long-break cycle.
    public private(set) var cyclePosition = 0
    /// Set when a phase finished naturally; the next phase waits here until
    /// the user starts it.
    public private(set) var pendingPhase: FocusPhase?

    public var isActive: Bool { phase != .idle }

    // MARK: Settings (persisted)

    public var focusMinutes: Int {
        didSet { defaults.set(focusMinutes, forKey: "focus.focusMinutes") }
    }
    public var shortBreakMinutes: Int {
        didSet { defaults.set(shortBreakMinutes, forKey: "focus.shortBreakMinutes") }
    }
    public var longBreakMinutes: Int {
        didSet { defaults.set(longBreakMinutes, forKey: "focus.longBreakMinutes") }
    }
    public var sessionsBeforeLongBreak: Int {
        didSet { defaults.set(sessionsBeforeLongBreak, forKey: "focus.sessionsBeforeLongBreak") }
    }
    public var keepAwakeDuringFocus: Bool {
        didSet { defaults.set(keepAwakeDuringFocus, forKey: "focus.keepAwake") }
    }

    // MARK: History

    public let history: FocusHistoryStore

    public var completedToday: Int { history.completedToday }

    @ObservationIgnored private var phaseTask: Task<Void, Never>?
    @ObservationIgnored private var phaseStartDate: Date?
    @ObservationIgnored private let defaults = UserDefaults.standard

    /// `history` is injectable for tests; defaults to the on-disk store.
    public init(history: FocusHistoryStore = FocusHistoryStore()) {
        self.history = history
        focusMinutes = defaults.object(forKey: "focus.focusMinutes") as? Int ?? 25
        shortBreakMinutes = defaults.object(forKey: "focus.shortBreakMinutes") as? Int ?? 5
        longBreakMinutes = defaults.object(forKey: "focus.longBreakMinutes") as? Int ?? 15
        sessionsBeforeLongBreak = defaults.object(forKey: "focus.sessionsBeforeLongBreak") as? Int ?? 4
        keepAwakeDuringFocus = defaults.object(forKey: "focus.keepAwake") as? Bool ?? true
    }

    // MARK: Controls

    public func start() {
        cyclePosition = 0
        enter(.focus)
    }

    public func pause() {
        guard isActive, !isPaused, let end = phaseEndDate else { return }
        phaseTask?.cancel()
        pausedRemaining = max(0, end.timeIntervalSinceNow)
        phaseEndDate = nil
        isPaused = true
        PowerAssertionService.shared.release(token: id)
    }

    public func resume() {
        guard isPaused, let remaining = pausedRemaining else { return }
        isPaused = false
        pausedRemaining = nil
        scheduleEnd(after: remaining)
        holdAssertionIfNeeded()
    }

    public func skip() {
        guard isActive, pendingPhase == nil else { return }
        advance(completedNaturally: false)
    }

    /// Starts the phase that is waiting after a natural completion.
    public func startPending() {
        guard let next = pendingPhase else { return }
        enter(next)
    }

    public func stop() {
        phaseTask?.cancel()
        phaseTask = nil
        phase = .idle
        phaseEndDate = nil
        pausedRemaining = nil
        pendingPhase = nil
        isPaused = false
        PowerAssertionService.shared.release(token: id)
    }

    /// Fraction of the current phase elapsed, for the progress ring.
    public func progress(at date: Date) -> Double {
        guard phaseDuration > 0 else { return 0 }
        let remaining: TimeInterval
        if let pausedRemaining {
            remaining = pausedRemaining
        } else if let end = phaseEndDate {
            remaining = max(0, end.timeIntervalSince(date))
        } else {
            return 0
        }
        return min(1, max(0, 1 - remaining / phaseDuration))
    }

    // MARK: Phase machine

    private func enter(_ newPhase: FocusPhase) {
        phaseTask?.cancel()
        isPaused = false
        pausedRemaining = nil
        pendingPhase = nil
        phase = newPhase
        phaseStartDate = .now

        let minutes = switch newPhase {
        case .idle: 0
        case .focus: focusMinutes
        case .shortBreak: shortBreakMinutes
        case .longBreak: longBreakMinutes
        }
        phaseDuration = TimeInterval(minutes * 60)
        scheduleEnd(after: phaseDuration)
        holdAssertionIfNeeded()
    }

    private func scheduleEnd(after seconds: TimeInterval) {
        phaseEndDate = Date.now.addingTimeInterval(seconds)
        phaseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.advance(completedNaturally: true)
        }
    }

    /// Internal so tests can simulate a phase finishing naturally.
    func advance(completedNaturally: Bool) {
        let finished = phase
        if finished == .focus {
            cyclePosition += 1
            if completedNaturally {
                history.record(FocusSession(
                    startDate: phaseStartDate ?? Date.now.addingTimeInterval(-phaseDuration),
                    endDate: .now,
                    duration: phaseDuration
                ))
            }
        }

        let next: FocusPhase
        if finished == .focus {
            next = cyclePosition >= sessionsBeforeLongBreak ? .longBreak : .shortBreak
            if next == .longBreak { cyclePosition = 0 }
        } else {
            next = .focus
        }

        if completedNaturally {
            phaseTask?.cancel()
            phaseTask = nil
            phaseEndDate = nil
            pausedRemaining = nil
            isPaused = false
            pendingPhase = next
            PowerAssertionService.shared.release(token: id)
            notifyTransition(from: finished, to: next)
        } else {
            enter(next)
        }
    }

    private func holdAssertionIfNeeded() {
        if phase == .focus && keepAwakeDuringFocus && !isPaused {
            PowerAssertionService.shared.hold(
                token: id,
                mode: .preventDisplaySleep,
                reason: "Eyrie Focus session"
            )
        } else {
            PowerAssertionService.shared.release(token: id)
        }
    }

    private func notifyTransition(from finished: FocusPhase, to next: FocusPhase) {
        let title: String
        let body: String
        switch next {
        case .shortBreak:
            title = "Focus complete"
            body = "Time for a \(shortBreakMinutes) minute break."
        case .longBreak:
            title = "Focus complete"
            body = "You earned a \(longBreakMinutes) minute long break."
        case .focus:
            title = "Break over"
            body = "Back to focus for \(focusMinutes) minutes."
        case .idle:
            return
        }
        Task { await NotificationService.shared.send(title: title, body: body) }
    }

    // MARK: EyrieModule views

    public var panelContent: AnyView { AnyView(FocusPanelView(module: self)) }
    public var settingsContent: AnyView { AnyView(FocusSettingsView(module: self)) }
}
