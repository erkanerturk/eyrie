import EyrieCore
import SwiftUI

struct TrafficSettingsView: View {
    @Bindable var module: TrafficModule

    var body: some View {
        Form {
            Section("Per-app traffic") {
                Toggle("Show per-app traffic", isOn: $module.showPerApp)
                Text("Reads the same per-process counters Activity Monitor uses (via nettop), only while the panel is open.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Show top", selection: $module.topCount) {
                    Text("3 apps").tag(3)
                    Text("5 apps").tag(5)
                    Text("8 apps").tag(8)
                }
            }
            Section("Daily usage") {
                Toggle("Track usage in the background", isOn: $module.backgroundTracking)
                Picker("Read counters every", selection: $module.backgroundIntervalMinutes) {
                    ForEach(TrafficModule.backgroundIntervalChoices, id: \.self) { minutes in
                        Text("\(minutes) minutes").tag(minutes)
                    }
                }
                .disabled(!module.backgroundTracking)
                Text("One lightweight counter reading per interval — no processes are launched. When off, daily totals only accumulate while the panel is open.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
