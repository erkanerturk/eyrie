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
        }
        .formStyle(.grouped)
    }
}
