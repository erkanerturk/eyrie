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
struct AwakeModuleTests {
    private func makeModule() -> AwakeModule {
        let module = AwakeModule()
        module.stop() // known clean state regardless of persisted defaults
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
