import SwiftUI
import EyrieCore

struct AwakeSettingsView: View {
    @Bindable var module: AwakeModule

    var body: some View {
        Form {
            Toggle("Allow display to sleep during sessions", isOn: $module.allowDisplaySleep)
            Text("The system stays awake either way; this only controls whether the screen may turn off.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Nudge after this long without input", selection: $module.activityInterval) {
                ForEach(AwakeActivityInterval.allCases) { interval in
                    Text(interval.label).tag(interval)
                }
            }
            Text("While Simulate activity is on, the pointer is nudged once you've been idle this long — pick a value below your chat app's away timeout. The 1 pt nudge can briefly wake the cursor, e.g. flashing playback controls over fullscreen video.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}
