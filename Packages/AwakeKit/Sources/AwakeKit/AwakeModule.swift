import SwiftUI
import EyrieCore

/// Keep-awake sessions backed by IOKit power assertions (Amphetamine core).
@MainActor
@Observable
public final class AwakeModule: EyrieModule {
    public let id = "awake"
    public let name = "Keep Awake"
    public var symbolName: String { isActive ? "cup.and.heat.waves.fill" : "cup.and.heat.waves" }

    public private(set) var isActive = false
    /// Nil while active means the session runs until manually stopped.
    public private(set) var sessionEndDate: Date?

    public var selectedPreset: AwakePreset {
        didSet { defaults.set(selectedPreset.rawValue, forKey: Self.presetKey) }
    }

    /// When true the display may sleep while the system stays awake.
    public var allowDisplaySleep: Bool {
        didSet {
            defaults.set(allowDisplaySleep, forKey: Self.displaySleepKey)
            if isActive { holdAssertion() }
        }
    }

    @ObservationIgnored private var sessionTask: Task<Void, Never>?
    @ObservationIgnored private let defaults = UserDefaults.standard

    private static let presetKey = "awake.preset"
    private static let displaySleepKey = "awake.allowDisplaySleep"

    public init() {
        selectedPreset = AwakePreset(rawValue: defaults.integer(forKey: Self.presetKey)) ?? .indefinite
        allowDisplaySleep = defaults.bool(forKey: Self.displaySleepKey)
    }

    public func start() {
        sessionTask?.cancel()
        guard holdAssertion() else { return }
        isActive = true

        if let minutes = selectedPreset.minutes {
            let end = Date.now.addingTimeInterval(TimeInterval(minutes * 60))
            sessionEndDate = end
            sessionTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(end.timeIntervalSinceNow))
                guard !Task.isCancelled else { return }
                self?.sessionExpired()
            }
        } else {
            sessionEndDate = nil
        }
    }

    public func stop() {
        sessionTask?.cancel()
        sessionTask = nil
        sessionEndDate = nil
        isActive = false
        PowerAssertionService.shared.release(token: id)
    }

    @discardableResult
    private func holdAssertion() -> Bool {
        PowerAssertionService.shared.hold(
            token: id,
            mode: allowDisplaySleep ? .allowDisplaySleep : .preventDisplaySleep,
            reason: "Eyrie Keep Awake session"
        )
    }

    private func sessionExpired() {
        stop()
        Task {
            await NotificationService.shared.send(
                title: "Keep Awake ended",
                body: "The session finished — your Mac can sleep again."
            )
        }
    }

    public var panelContent: AnyView { AnyView(AwakePanelView(module: self)) }
    public var panelAccessory: AnyView { AnyView(AwakeToggle(module: self)) }
    public var settingsContent: AnyView { AnyView(AwakeSettingsView(module: self)) }
}

public enum AwakePreset: Int, CaseIterable, Identifiable, Sendable {
    case indefinite = 0
    case minutes15 = 15
    case minutes30 = 30
    case hour1 = 60
    case hours2 = 120
    case hours4 = 240
    case hours8 = 480

    public var id: Int { rawValue }

    /// Nil means run indefinitely.
    public var minutes: Int? { self == .indefinite ? nil : rawValue }

    public var label: String {
        switch self {
        case .indefinite: "Indefinitely"
        case .minutes15: "15 minutes"
        case .minutes30: "30 minutes"
        case .hour1: "1 hour"
        case .hours2: "2 hours"
        case .hours4: "4 hours"
        case .hours8: "8 hours"
        }
    }
}
