import CoreAudio
import Foundation

/// An output-capable audio device as shown in the share list.
struct AudioOutputDevice: Identifiable, Hashable, Sendable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let transportType: UInt32

    var isBluetooth: Bool {
        transportType == kAudioDeviceTransportTypeBluetooth
            || transportType == kAudioDeviceTransportTypeBluetoothLE
    }
}

/// Thin, synchronous CoreAudio helpers. All calls are cheap property reads/writes.
enum CoreAudioSupport {
    private static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    private static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    // MARK: Device discovery

    static func outputDevices() -> [AudioOutputDevice] {
        allDeviceIDs().compactMap { id in
            guard outputChannelCount(of: id) > 0 else { return nil }
            let transport = transportType(of: id)
            // Skip aggregates (including our own) and virtual/null devices.
            guard transport != kAudioDeviceTransportTypeAggregate,
                  transport != kAudioDeviceTransportTypeVirtual,
                  transport != kAudioDeviceTransportTypeUnknown else { return nil }
            guard let uid = stringProperty(of: id, selector: kAudioDevicePropertyDeviceUID),
                  let name = stringProperty(of: id, selector: kAudioDevicePropertyDeviceNameCFString)
            else { return nil }
            return AudioOutputDevice(id: id, uid: uid, name: name, transportType: transport)
        }
    }

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(systemObject, &addr, 0, nil, &size) == noErr,
              size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(systemObject, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func outputChannelCount(of device: AudioDeviceID) -> Int {
        var addr = address(kAudioDevicePropertyStreamConfiguration, scope: kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let listPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { listPointer.deallocate() }
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, listPointer) == noErr else { return 0 }
        let buffers = UnsafeMutableAudioBufferListPointer(listPointer.assumingMemoryBound(to: AudioBufferList.self))
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func transportType(of device: AudioDeviceID) -> UInt32 {
        var addr = address(kAudioDevicePropertyTransportType)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr else {
            return kAudioDeviceTransportTypeUnknown
        }
        return value
    }

    private static func stringProperty(of device: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var addr = address(selector)
        var value: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(device, &addr, 0, nil, &size, pointer)
        }
        guard status == noErr, let value else { return nil }
        return value as String
    }

    // MARK: Default output device

    static func defaultOutputDevice() -> AudioDeviceID? {
        var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
        var value = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(systemObject, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    @discardableResult
    static func setDefaultOutputDevice(_ device: AudioDeviceID) -> Bool {
        var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
        var value = device
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        return AudioObjectSetPropertyData(systemObject, &addr, 0, nil, size, &value) == noErr
    }

    static func uid(of device: AudioDeviceID) -> String? {
        stringProperty(of: device, selector: kAudioDevicePropertyDeviceUID)
    }

    // MARK: Aggregate (multi-output) device

    /// Creates a stacked (multi-output) aggregate from the given device UIDs.
    /// The first UID acts as the master clock; all others get drift compensation.
    static func createMultiOutputDevice(name: String, uid: String, deviceUIDs: [String]) -> AudioDeviceID? {
        guard let masterUID = deviceUIDs.first else { return nil }

        let subDevices: [[String: Any]] = deviceUIDs.map { deviceUID in
            [
                kAudioSubDeviceUIDKey: deviceUID,
                kAudioSubDeviceDriftCompensationKey: deviceUID == masterUID ? 0 : 1,
            ]
        }
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: name,
            kAudioAggregateDeviceUIDKey: uid,
            kAudioAggregateDeviceIsStackedKey: 1,
            kAudioAggregateDeviceMainSubDeviceKey: masterUID,
            kAudioAggregateDeviceSubDeviceListKey: subDevices,
        ]

        var aggregateID = AudioDeviceID(0)
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID)
        guard status == noErr, aggregateID != 0 else { return nil }
        return aggregateID
    }

    @discardableResult
    static func destroyAggregateDevice(_ device: AudioDeviceID) -> Bool {
        AudioHardwareDestroyAggregateDevice(device) == noErr
    }

    // MARK: Per-device volume

    private static func volumeAddresses(for device: AudioDeviceID) -> [AudioObjectPropertyAddress] {
        let main = address(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeOutput)
        var mainCopy = main
        if AudioObjectHasProperty(device, &mainCopy) {
            return [main]
        }
        // Devices without a main-element volume expose per-channel controls.
        return (1...2).map {
            address(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeOutput, element: AudioObjectPropertyElement($0))
        }
    }

    static func volume(of device: AudioDeviceID) -> Float? {
        for var addr in volumeAddresses(for: device) {
            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr {
                return value
            }
        }
        return nil
    }

    static func setVolume(_ volume: Float, of device: AudioDeviceID) {
        for var addr in volumeAddresses(for: device) {
            var value = Float32(min(max(volume, 0), 1))
            let size = UInt32(MemoryLayout<Float32>.size)
            AudioObjectSetPropertyData(device, &addr, 0, nil, size, &value)
        }
    }

    // MARK: Change notifications

    /// Invokes `onChange` on the main queue whenever the device list changes.
    static func observeDeviceListChanges(_ onChange: @escaping @Sendable () -> Void) {
        var addr = address(kAudioHardwarePropertyDevices)
        AudioObjectAddPropertyListenerBlock(systemObject, &addr, .main) { _, _ in
            onChange()
        }
    }
}
