import Foundation
import Testing
import EyrieCore
@testable import AwakeKit

struct AwakePresetTests {
    @Test func indefiniteHasNoDuration() {
        #expect(AwakePreset.indefinite.minutes == nil)
    }

    @Test func timedPresetsMapToTheirRawMinutes() {
        #expect(AwakePreset.minutes15.minutes == 15)
        #expect(AwakePreset.minutes30.minutes == 30)
        #expect(AwakePreset.hour1.minutes == 60)
        #expect(AwakePreset.hours8.minutes == 480)
    }

    @Test func allPresetsHaveLabels() {
        for preset in AwakePreset.allCases {
            #expect(!preset.label.isEmpty)
        }
    }
}

@MainActor
private final class TrustBox {
    var trusted = true
}

@MainActor
struct AwakeModuleTests {
    private static let suiteName = "AwakeKitTests"

    /// A wiped, app-independent domain — tests must never write the real
    /// preferences through the toggles' `didSet`.
    private func makeDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: Self.suiteName)!
        defaults.removePersistentDomain(forName: Self.suiteName)
        return defaults
    }

    private func makeModule(trustedBox: TrustBox = TrustBox()) -> AwakeModule {
        let module = AwakeModule(defaults: makeDefaults(), trustCheck: { trustedBox.trusted })
        module.stop() // known clean state regardless of prior assertions
        return module
    }

    @Test func indefiniteSessionHasNoEndDate() {
        let module = makeModule()
        module.selectedPreset = .indefinite
        module.start()

        #expect(module.isActive)
        #expect(module.sessionEndDate == nil)
        #expect(PowerAssertionService.shared.isHoldingAssertion)

        module.stop()
        #expect(!module.isActive)
        #expect(!PowerAssertionService.shared.isHoldingAssertion)
    }

    @Test func timedSessionSetsEndDate() {
        let module = makeModule()
        module.selectedPreset = .minutes15
        module.start()
        defer { module.stop() }

        let expected = Date.now.addingTimeInterval(15 * 60)
        let end = try! #require(module.sessionEndDate)
        #expect(abs(end.timeIntervalSince(expected)) < 5)
    }

    @Test func restartReplacesSession() {
        let module = makeModule()
        module.selectedPreset = .minutes15
        module.start()
        module.selectedPreset = .indefinite
        module.start()
        defer { module.stop() }

        #expect(module.isActive)
        #expect(module.sessionEndDate == nil, "second start must replace the timed session")
    }

    @Test func symbolReflectsActivity() {
        let module = makeModule()
        #expect(module.symbolName == "cup.and.heat.waves")
        module.selectedPreset = .indefinite
        module.start()
        #expect(module.symbolName == "cup.and.heat.waves.fill")
        module.stop()
        #expect(module.symbolName == "cup.and.heat.waves")
    }

    @Test func simulatorWaitsForModuleEnable() {
        let module = makeModule()
        defer { module.setModuleEnabled(false) }

        module.simulateActivity = true
        #expect(!module.isSimulatingActivity, "the registry hasn't enabled the module yet")

        module.setModuleEnabled(true)
        #expect(module.isSimulatingActivity)
        #expect(module.isActive, "simulation alone must light up the menu bar icon")
        #expect(!module.isSessionActive, "no power assertion session was started")

        module.simulateActivity = false
        #expect(!module.isSimulatingActivity)
        #expect(!module.isActive)
    }

    @Test func disablingModuleStopsSimulatorAndReenableRestoresIt() {
        let module = makeModule()
        defer { module.setModuleEnabled(false) }

        module.setModuleEnabled(true)
        module.simulateActivity = true
        #expect(module.isSimulatingActivity)

        module.setModuleEnabled(false)
        #expect(!module.isSimulatingActivity)

        module.setModuleEnabled(true)
        #expect(module.isSimulatingActivity, "re-enable must restore the in-memory switch state")
    }

    @Test func simulateActivityIsSessionOnly() {
        let defaults = makeDefaults()
        let module = AwakeModule(defaults: defaults, trustCheck: { true })
        module.setModuleEnabled(true)
        module.simulateActivity = true
        module.shutdown()

        // A relaunch constructs a fresh module over the same defaults; the
        // switch must come back off, like Keep Awake.
        let relaunched = AwakeModule(defaults: defaults, trustCheck: { true })
        relaunched.setModuleEnabled(true)
        #expect(!relaunched.simulateActivity)
        #expect(!relaunched.isSimulatingActivity)
    }

    @Test func legacyPersistedSwitchIsClearedAndIgnored() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "awake.simulateActivity") // written by ≤ v0.5.1

        let module = AwakeModule(defaults: defaults, trustCheck: { true })
        module.setModuleEnabled(true)
        #expect(!module.simulateActivity, "the legacy value must not resurrect the switch")
        #expect(!module.isSimulatingActivity)
        #expect(defaults.object(forKey: "awake.simulateActivity") == nil, "the stale key is cleaned up")
    }

    @Test func shutdownStopsSimulatorAndStaysStopped() {
        let module = makeModule()

        module.setModuleEnabled(true)
        module.simulateActivity = true
        module.shutdown()
        #expect(!module.isSimulatingActivity)

        // shutdown() also clears the enabled flag, so a stray sync can't
        // restart the loop mid-termination.
        module.refreshAccessibilityTrust()
        #expect(!module.isSimulatingActivity)
    }

    @Test func untrustedSimulatorDoesNotReportActive() {
        let box = TrustBox()
        box.trusted = false
        let module = makeModule(trustedBox: box)
        defer { module.setModuleEnabled(false) }

        module.setModuleEnabled(true)
        module.simulateActivity = true
        #expect(!module.hasAccessibilityTrust)
        #expect(!module.isSimulatingActivity, "an undelivered nudge must not present as simulating")
        #expect(!module.isActive)

        box.trusted = true
        module.refreshAccessibilityTrust() // what the tick loop does each tick
        #expect(module.hasAccessibilityTrust)
        #expect(module.isSimulatingActivity)
        #expect(module.isActive)
    }

    @Test func symbolTracksSessionNotSimulation() {
        let module = makeModule()
        defer { module.setModuleEnabled(false) }

        module.setModuleEnabled(true)
        module.simulateActivity = true
        #expect(module.isActive)
        #expect(module.symbolName == "cup.and.heat.waves",
                "the cup means a power assertion; simulation alone must not fill it")
    }

    @Test func activityIntervalPersists() {
        let defaults = makeDefaults()
        let module = AwakeModule(defaults: defaults, trustCheck: { true })
        module.activityInterval = .minutes5

        let fresh = AwakeModule(defaults: defaults, trustCheck: { true })
        #expect(fresh.activityInterval == .minutes5)
    }

    @Test func togglingDisplaySleepWhileActiveKeepsAssertion() {
        let module = makeModule()
        module.selectedPreset = .indefinite
        module.allowDisplaySleep = false
        module.start()

        module.allowDisplaySleep = true
        #expect(PowerAssertionService.shared.isHoldingAssertion, "mode change must re-hold, not drop, the assertion")

        module.stop()
        #expect(!PowerAssertionService.shared.isHoldingAssertion)
    }
}
