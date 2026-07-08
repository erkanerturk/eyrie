import Foundation
import IOKit.pwr_mgt
import Testing
@testable import EyrieCore

/// These tests create real (short-lived) IOKit power assertions and release
/// them before returning, so they leave no trace in `pmset -g assertions`.
@MainActor
struct PowerAssertionServiceTests {
    @Test func holdAndReleaseSingleToken() {
        let service = PowerAssertionService.shared
        #expect(service.hold(token: "test.single", mode: .allowDisplaySleep, reason: "Eyrie unit test"))
        #expect(service.isHoldingAssertion)

        service.release(token: "test.single")
        #expect(!service.isHoldingAssertion)
    }

    @Test func tokensAreIndependent() {
        let service = PowerAssertionService.shared
        service.hold(token: "test.a", mode: .allowDisplaySleep, reason: "Eyrie unit test")
        service.hold(token: "test.b", mode: .preventDisplaySleep, reason: "Eyrie unit test")

        service.release(token: "test.a")
        #expect(service.isHoldingAssertion, "releasing one token must not release the other")

        service.release(token: "test.b")
        #expect(!service.isHoldingAssertion)
    }

    @Test func reholdingSameTokenDoesNotLeak() {
        let service = PowerAssertionService.shared
        service.hold(token: "test.rehold", mode: .allowDisplaySleep, reason: "Eyrie unit test")
        service.hold(token: "test.rehold", mode: .preventDisplaySleep, reason: "Eyrie unit test")

        // A single release must drop the only remaining assertion.
        service.release(token: "test.rehold")
        #expect(!service.isHoldingAssertion)
    }

    @Test func releaseAllClearsEverything() {
        let service = PowerAssertionService.shared
        service.hold(token: "test.x", mode: .allowDisplaySleep, reason: "Eyrie unit test")
        service.hold(token: "test.y", mode: .allowDisplaySleep, reason: "Eyrie unit test")

        service.releaseAll()
        #expect(!service.isHoldingAssertion)
    }

    @Test func releasingUnknownTokenIsHarmless() {
        let service = PowerAssertionService.shared
        service.release(token: "test.never-held")
        #expect(!service.isHoldingAssertion)
    }

    /// Verifies the assertion is actually registered with powerd, not just
    /// tracked in our own state.
    @Test func holdRegistersSystemVisibleAssertion() {
        let service = PowerAssertionService.shared
        let marker = "Eyrie unit test marker \(UUID().uuidString)"
        #expect(service.hold(token: "test.visible", mode: .allowDisplaySleep, reason: marker))
        defer { service.release(token: "test.visible") }

        var assertionsRef: Unmanaged<CFDictionary>?
        #expect(IOPMCopyAssertionsByProcess(&assertionsRef) == kIOReturnSuccess)
        let byProcess = assertionsRef?.takeRetainedValue() as NSDictionary?

        let ourEntries = byProcess?.compactMap { key, value -> [[String: Any]]? in
            guard let pid = (key as? NSNumber)?.int32Value, pid == getpid() else { return nil }
            return value as? [[String: Any]]
        }.flatMap(\.self) ?? []

        #expect(ourEntries.contains { ($0[kIOPMAssertionNameKey as String] as? String) == marker })
    }
}
