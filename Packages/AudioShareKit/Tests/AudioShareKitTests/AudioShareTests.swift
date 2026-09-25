import CoreAudio
import Foundation
import Testing
@testable import AudioShareKit

struct AudioOutputDeviceTests {
    private func device(transport: UInt32) -> AudioOutputDevice {
        AudioOutputDevice(id: 1, uid: "test-uid", name: "Test", transportType: transport)
    }

    @Test func bluetoothTransportsAreFlagged() {
        #expect(device(transport: kAudioDeviceTransportTypeBluetooth).isBluetooth)
        #expect(device(transport: kAudioDeviceTransportTypeBluetoothLE).isBluetooth)
        #expect(!device(transport: kAudioDeviceTransportTypeBuiltIn).isBluetooth)
        #expect(!device(transport: kAudioDeviceTransportTypeUSB).isBluetooth)
    }
}

/// Read-only checks against the real CoreAudio HAL — they enumerate and read
/// properties but never change routing or create devices.
struct CoreAudioSupportTests {
    @Test func outputDevicesAreWellFormed() {
        for device in CoreAudioSupport.outputDevices() {
            #expect(!device.uid.isEmpty)
            #expect(!device.name.isEmpty)
            #expect(device.transportType != kAudioDeviceTransportTypeAggregate, "aggregates must be filtered out")
        }
    }

    @Test func defaultOutputDeviceExists() {
        let device = CoreAudioSupport.defaultOutputDevice()
        #expect(device != nil)
        if let device {
            #expect(CoreAudioSupport.uid(of: device) != nil)
        }
    }

    /// Creates a single-device stacked aggregate and immediately destroys it.
    /// The default output is never touched; this is the same transient churn
    /// as plugging in headphones.
    @Test func aggregateCreateAndDestroyRoundTrip() throws {
        let defaultBefore = CoreAudioSupport.defaultOutputDevice()
        let anyOutput = try #require(CoreAudioSupport.outputDevices().first)

        let aggregate = try #require(CoreAudioSupport.createMultiOutputDevice(
            name: "Eyrie Test Aggregate",
            uid: "com.erkanerturk.eyrie.test.\(UUID().uuidString)",
            deviceUIDs: [anyOutput.uid]
        ))
        #expect(CoreAudioSupport.destroyAggregateDevice(aggregate))
        #expect(CoreAudioSupport.defaultOutputDevice() == defaultBefore, "default output must be untouched")
    }

    @Test func deviceLookupByUID() throws {
        #expect(CoreAudioSupport.device(forUID: "com.erkanerturk.eyrie.test.missing") == nil)
        let anyOutput = try #require(CoreAudioSupport.outputDevices().first)
        #expect(CoreAudioSupport.device(forUID: anyOutput.uid) == anyOutput.id)
    }

    /// coreaudiod publishes and removes aggregates asynchronously (~50 ms
    /// measured), so UID lookups right after create/destroy must poll.
    private func lookUp(_ uid: String, untilPresent present: Bool) -> AudioDeviceID? {
        var device = CoreAudioSupport.device(forUID: uid)
        for _ in 0..<40 where (device != nil) != present {
            usleep(50_000)
            device = CoreAudioSupport.device(forUID: uid)
        }
        return device
    }

    /// A leftover aggregate that isn't the default output is simply removed;
    /// the default output is never touched.
    @Test func orphanedAggregateIsRemoved() throws {
        let defaultBefore = CoreAudioSupport.defaultOutputDevice()
        let anyOutput = try #require(CoreAudioSupport.outputDevices().first)
        let uid = "com.erkanerturk.eyrie.test.\(UUID().uuidString)"
        let aggregate = try #require(CoreAudioSupport.createMultiOutputDevice(
            name: "Eyrie Test Aggregate", uid: uid, deviceUIDs: [anyOutput.uid]
        ))
        defer { CoreAudioSupport.destroyAggregateDevice(aggregate) }
        #expect(lookUp(uid, untilPresent: true) == aggregate)

        AudioShareModule.removeOrphanedAggregate(uid: uid, restoreTo: nil)
        #expect(lookUp(uid, untilPresent: false) == nil)
        #expect(CoreAudioSupport.defaultOutputDevice() == defaultBefore, "default output must be untouched")
    }

    @Test func emptyAggregateIsRejected() {
        #expect(CoreAudioSupport.createMultiOutputDevice(name: "x", uid: "y", deviceUIDs: []) == nil)
    }
}

@MainActor
struct AudioShareModuleTests {
    private func makeModule() -> AudioShareModule {
        UserDefaults.standard.removeObject(forKey: "audioshare.selected")
        return AudioShareModule()
    }

    @Test func selectionTogglesAndPersists() {
        let module = makeModule()
        let fake = AudioOutputDevice(id: 42, uid: "fake-uid", name: "Fake", transportType: kAudioDeviceTransportTypeBluetooth)

        module.setSelected(true, device: fake)
        #expect(module.isSelected(fake))

        let reloaded = AudioShareModule()
        #expect(reloaded.isSelected(fake), "selection must survive relaunch")

        module.setSelected(false, device: fake)
        #expect(!module.isSelected(fake))
    }

    @Test func selectedDevicesOnlyCountPresentHardware() {
        let module = makeModule()
        let ghost = AudioOutputDevice(id: 43, uid: "ghost-uid", name: "Ghost", transportType: kAudioDeviceTransportTypeBluetooth)

        module.setSelected(true, device: ghost)
        #expect(!module.selectedDevices.contains(where: { $0.uid == ghost.uid }),
                "a selected but disconnected device must not count toward sharing")
    }

    @Test func sharingRequiresTwoPresentDevices() {
        let module = makeModule()
        // Fresh module: nothing selected, so sharing must refuse to start.
        module.startSharing()
        #expect(!module.isActive)
    }

    @Test func stopWithoutStartIsHarmless() {
        let module = makeModule()
        module.stopSharing()
        module.shutdown()
        #expect(!module.isActive)
    }
}
