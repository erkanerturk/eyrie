import SwiftUI
import EyrieCore

struct AudioSharePanelView: View {
    @Bindable var module: AudioShareModule

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if module.devices.isEmpty {
                Text("No output devices found")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(module.devices) { device in
                    deviceRow(device)
                }
                if !module.canShare {
                    Text("Select at least two devices to share audio")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
        }
        .onAppear { module.refreshDevices() }
    }

    @ViewBuilder
    private func deviceRow(_ device: AudioOutputDevice) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(
                get: { module.isSelected(device) },
                set: { module.setSelected($0, device: device) }
            )) {
                Label {
                    Text(device.name).lineLimit(1)
                } icon: {
                    Image(systemName: device.isBluetooth ? "airpods.gen3" : "hifispeaker")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }
            .toggleStyle(.checkbox)

            if module.isActive && module.isSelected(device) {
                Slider(
                    value: Binding(
                        get: { module.volumes[device.uid] ?? 0.5 },
                        set: { module.setVolume($0, for: device) }
                    ),
                    in: 0...1
                ) {
                    EmptyView()
                } minimumValueLabel: {
                    Image(systemName: "speaker.fill").font(.caption2)
                } maximumValueLabel: {
                    Image(systemName: "speaker.wave.3.fill").font(.caption2)
                }
                .controlSize(.mini)
                .padding(.leading, 22)
            }
        }
    }
}

struct AudioShareToggle: View {
    @Bindable var module: AudioShareModule

    var body: some View {
        Toggle("Share Audio", isOn: Binding(
            get: { module.isActive },
            set: { $0 ? module.startSharing() : module.stopSharing() }
        ))
        .labelsHidden()
        .toggleStyle(.switch)
        .controlSize(.small)
        .disabled(!module.isActive && !module.canShare)
    }
}
