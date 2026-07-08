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
