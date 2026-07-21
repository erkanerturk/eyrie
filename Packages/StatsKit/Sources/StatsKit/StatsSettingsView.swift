import SwiftUI
import EyrieCore

struct StatsSettingsView: View {
    @Bindable var module: StatsModule

    var body: some View {
        Form {
            Picker("Update every", selection: $module.samplingInterval) {
                Text("1 second").tag(1.0)
                Text("2 seconds").tag(2.0)
                Text("5 seconds").tag(5.0)
            }
            Text("Stats are only sampled while the panel is open, so a shorter interval has no cost when the menu is closed.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Section("Metrics") {
                Toggle("CPU", isOn: $module.showCPU)
                Toggle("Memory", isOn: $module.showMemory)
                Toggle("Network", isOn: $module.showNetwork)
            }

            Section("Appearance") {
                Toggle("Show graphs", isOn: $module.showGraphs)
                Text("Hiding the sparklines leaves just the numbers, for a shorter card.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
