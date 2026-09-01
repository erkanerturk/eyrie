import ApplicationServices
import CoreGraphics
import Foundation

/// Posts a tiny synthetic mouse move once the user has been idle for the
/// configured threshold — and again every threshold while they stay idle — so
/// presence-based apps (Teams, Slack, …) don't flip the user to "away" on a
/// machine Keep Awake is holding open.
///
/// The model is an idle threshold, not a fixed-period timer: each check is
/// scheduled for the moment the HID idle clock can actually cross the
/// threshold (`interval - idleTime()`), so the first nudge lands within a
/// bounded delay of the user's last real input instead of drifting up to 2x.
/// A nudge fires only when the idle time covers the whole threshold, so it
/// never fights real input, and the loop always sleeps before the first
/// check — enabling the switch never moves the pointer immediately.
@MainActor
final class ActivitySimulator {
    private(set) var isRunning = false

    /// Idle threshold in seconds; also the re-nudge period while idle persists.
    var interval: TimeInterval

    /// Called at the start of every tick, before the idle check — the module
    /// uses it to re-poll the Accessibility grant while the loop is running.
    var onTick: (@MainActor () -> Void)?

    private let idleTime: @MainActor () -> TimeInterval
    private let nudge: @MainActor () -> Void
    private var task: Task<Void, Never>?

    init(
        interval: TimeInterval,
        idleTime: @escaping @MainActor () -> TimeInterval = ActivitySimulator.systemIdleTime,
        nudge: @escaping @MainActor () -> Void = ActivitySimulator.postMouseNudge
    ) {
        self.interval = interval
        self.idleTime = idleTime
        self.nudge = nudge
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        task = Task { [weak self] in
            // After a nudge attempt, sleep a flat interval: nextWait() assumes
            // the nudge reset the idle clock, and when it didn't (Accessibility
            // not granted, posts dropped) the 1 s clamp would otherwise become
            // the schedule and spin the loop at 1 Hz.
            var justNudged = false
            while !Task.isCancelled {
                guard let wait = self.map({ justNudged ? $0.interval : $0.nextWait() }) else { return }
                try? await Task.sleep(for: .seconds(wait))
                guard !Task.isCancelled, let self else { return }
                justNudged = self.tick()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    /// Sleep until the idle clock can actually cross the threshold (never
    /// less than 1 s, so a stuck idle clock can't turn this into a hot loop).
    func nextWait() -> TimeInterval {
        max(1, interval - idleTime())
    }

    /// One idle check; split from the loop so tests drive it synchronously.
    /// Returns whether a nudge was attempted, so the loop can rate-limit to
    /// one attempt per threshold even when delivery silently fails.
    @discardableResult
    func tick() -> Bool {
        onTick?()
        guard idleTime() >= interval else { return false }
        nudge()
        return true
    }

    // MARK: - System implementations

    /// `kCGAnyInputEventType` isn't imported into Swift; its C definition is
    /// `((CGEventType)(~0))`.
    static func systemIdleTime() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: CGEventType(rawValue: ~0)!
        )
    }

    /// Moves the pointer 1 pt right and immediately back. Both events reset
    /// the HID idle clock; restoring keeps the cursor visually in place.
    static func postMouseNudge() {
        guard let location = CGEvent(source: nil)?.location else { return }
        let nudged = CGPoint(x: location.x + 1, y: location.y)
        for point in [nudged, location] {
            CGEvent(
                mouseEventSource: nil,
                mouseType: .mouseMoved,
                mouseCursorPosition: point,
                mouseButton: .left
            )?.post(tap: .cghidEventTap)
        }
    }

    /// Posting synthetic events needs the Accessibility (TCC) grant.
    static var hasAccessibilityTrust: Bool { AXIsProcessTrusted() }

    static func promptForAccessibilityTrust() {
        // The unbundled swift-test runner must never raise the TCC prompt
        // (same guard as NotificationService).
        guard Bundle.main.bundleIdentifier != nil else { return }
        // Literal key: `kAXTrustedCheckOptionPrompt` is a C global Swift 6
        // rejects as shared mutable state.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}

/// How often the simulator checks for idleness and nudges the pointer.
public enum AwakeActivityInterval: Int, CaseIterable, Identifiable, Sendable {
    case seconds30 = 30
    case minute1 = 60
    case minutes2 = 120
    case minutes5 = 300

    public var id: Int { rawValue }

    public var seconds: TimeInterval { TimeInterval(rawValue) }

    public var label: String {
        switch self {
        case .seconds30: "30 seconds"
        case .minute1: "1 minute"
        case .minutes2: "2 minutes"
        case .minutes5: "5 minutes"
        }
    }
}
