import Foundation
import IOKit.pwr_mgt
import Observation

/// Central owner of IOKit power assertions. Multiple modules can hold
/// assertions at the same time (e.g. an Awake session and a Focus session);
/// each holds its own token and the system stays awake until all are released.
@MainActor
@Observable
public final class PowerAssertionService {
    public static let shared = PowerAssertionService()

    public enum Mode: String, Sendable {
        /// Keep the system awake but let the display sleep.
        case allowDisplaySleep
        /// Keep both the system and the display awake.
        case preventDisplaySleep

        var assertionType: CFString {
            switch self {
            case .allowDisplaySleep: kIOPMAssertionTypePreventUserIdleSystemSleep as CFString
            case .preventDisplaySleep: kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString
            }
        }
    }

    private var assertions: [String: IOPMAssertionID] = [:]

    public private(set) var isHoldingAssertion = false

    private init() {}

    /// Creates (or replaces) the assertion held under `token`.
    @discardableResult
    public func hold(token: String, mode: Mode, reason: String) -> Bool {
        release(token: token)

        var assertionID = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            mode.assertionType,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertionID
        )
        guard result == kIOReturnSuccess else { return false }
        assertions[token] = assertionID
        isHoldingAssertion = true
        return true
    }

    public func release(token: String) {
        if let id = assertions.removeValue(forKey: token) {
            IOPMAssertionRelease(id)
        }
        isHoldingAssertion = !assertions.isEmpty
    }

    public func releaseAll() {
        for id in assertions.values {
            IOPMAssertionRelease(id)
        }
        assertions.removeAll()
        isHoldingAssertion = false
    }
}
