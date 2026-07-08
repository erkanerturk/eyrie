import SwiftUI
import CoreAudio
import EyrieCore

/// Simultaneous audio on multiple output devices via a stacked aggregate
/// device (PairPods core).
@MainActor
@Observable
public final class AudioShareModule: EyrieModule {
    public let id = "audioshare"
    public let name = "Audio Share"
    public var symbolName: String { isActive ? "airpods.pro" : "hifispeaker.2" }

    public private(set) var isActive = false

    private(set) var devices: [AudioOutputDevice] = []
    private(set) var selectedUIDs: Set<String> {
        didSet { UserDefaults.standard.set(Array(selectedUIDs), forKey: "audioshare.selected") }
    }
    /// Volume slider state per device, keyed by UID.
    private(set) var volumes: [String: Float] = [:]

    @ObservationIgnored private var aggregateID: AudioDeviceID?
    @ObservationIgnored private var previousDefaultUID: String?

    private static let aggregateUID = "com.erkanerturk.eyrie.audioshare"

    public init() {
        selectedUIDs = Set(UserDefaults.standard.stringArray(forKey: "audioshare.selected") ?? [])
        refreshDevices()
        CoreAudioSupport.observeDeviceListChanges { [weak self] in
            Task { @MainActor in self?.handleDeviceListChange() }
        }
    }

    // MARK: Device list

    func refreshDevices() {
        devices = CoreAudioSupport.outputDevices()
            .sorted { ($0.isBluetooth ? 0 : 1, $0.name) < ($1.isBluetooth ? 0 : 1, $1.name) }
        for device in devices where volumes[device.uid] == nil {
            volumes[device.uid] = CoreAudioSupport.volume(of: device.id) ?? 0.5
        }
    }

    private func handleDeviceListChange() {
        refreshDevices()
        // If a shared device disappeared (e.g. AirPods went in the case), rebuild
        // the aggregate with whatever is still present, or stop entirely.
        guard isActive else { return }
        let present = Set(devices.map(\.uid))
        let stillShared = selectedUIDs.intersection(present)
        if stillShared.count < 2 {
            stopSharing()
        } else if stillShared != participatingUIDs {
            restartSharing()
        }
    }

    // MARK: Selection

    var selectedDevices: [AudioOutputDevice] {
        devices.filter { selectedUIDs.contains($0.uid) }
    }

    var canShare: Bool { selectedDevices.count >= 2 }

    func isSelected(_ device: AudioOutputDevice) -> Bool {
        selectedUIDs.contains(device.uid)
    }

    func setSelected(_ selected: Bool, device: AudioOutputDevice) {
        if selected {
            selectedUIDs.insert(device.uid)
        } else {
            selectedUIDs.remove(device.uid)
        }
        if isActive {
            canShare ? restartSharing() : stopSharing()
        }
    }

    // MARK: Sharing lifecycle

    /// UIDs actually inside the current aggregate (selection may change while sharing).
    @ObservationIgnored private var participatingUIDs: Set<String> = []

    func startSharing() {
        guard !isActive, canShare else { return }

        // Bluetooth device first as master clock: BT clocks drift the most, so
        // everything else compensates against it.
        let ordered = selectedDevices
        guard let aggregate = CoreAudioSupport.createMultiOutputDevice(
            name: "Eyrie Audio Share",
            uid: Self.aggregateUID,
            deviceUIDs: ordered.map(\.uid)
        ) else { return }

        if let current = CoreAudioSupport.defaultOutputDevice() {
            previousDefaultUID = CoreAudioSupport.uid(of: current)
        }
        aggregateID = aggregate
        participatingUIDs = Set(ordered.map(\.uid))
        CoreAudioSupport.setDefaultOutputDevice(aggregate)
        isActive = true
    }

    func stopSharing() {
        guard let aggregate = aggregateID else {
            isActive = false
            return
        }
        // Restore the previous output before tearing the aggregate down so the
        // system never routes to a dying device.
        if let previousUID = previousDefaultUID,
           let previous = devices.first(where: { $0.uid == previousUID }) {
            CoreAudioSupport.setDefaultOutputDevice(previous.id)
        } else if let fallback = selectedDevices.first ?? devices.first {
            CoreAudioSupport.setDefaultOutputDevice(fallback.id)
        }
        CoreAudioSupport.destroyAggregateDevice(aggregate)
        aggregateID = nil
        participatingUIDs = []
        previousDefaultUID = nil
        isActive = false
    }

    private func restartSharing() {
        let previous = previousDefaultUID
        stopSharing()
        previousDefaultUID = previous
        startSharing()
    }

    // MARK: Volume

    func setVolume(_ volume: Float, for device: AudioOutputDevice) {
        volumes[device.uid] = volume
        CoreAudioSupport.setVolume(volume, of: device.id)
    }

    public func shutdown() {
        stopSharing()
    }

    // MARK: EyrieModule views

    public var panelContent: AnyView { AnyView(AudioSharePanelView(module: self)) }
    public var panelAccessory: AnyView { AnyView(AudioShareToggle(module: self)) }
}
