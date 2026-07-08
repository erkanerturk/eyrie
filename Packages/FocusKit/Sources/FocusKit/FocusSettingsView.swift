import SwiftUI
import EyrieCore

struct FocusSettingsView: View {
    @Bindable var module: FocusModule

    var body: some View {
        Form {
            Section("Durations") {
                Stepper("Focus: \(module.focusMinutes) min", value: $module.focusMinutes, in: 5...120, step: 5)
                Stepper("Short break: \(module.shortBreakMinutes) min", value: $module.shortBreakMinutes, in: 1...30)
                Stepper("Long break: \(module.longBreakMinutes) min", value: $module.longBreakMinutes, in: 5...60, step: 5)
                Stepper("Long break after \(module.sessionsBeforeLongBreak) sessions", value: $module.sessionsBeforeLongBreak, in: 2...8)
            }
            Section {
                Toggle("Keep Mac awake during focus", isOn: $module.keepAwakeDuringFocus)
            }
            Section("Statistics") {
                FocusStatisticsView(history: module.history)
            }
        }
        .formStyle(.grouped)
    }
}
