import SwiftUI
import EyrieCore

struct AwakePanelView: View {
    @Bindable var module: AwakeModule

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if module.isActive {
                HStack(spacing: 6) {
                    Image(systemName: "moon.zzz.fill")
                        .foregroundStyle(.tint)
                    if let end = module.sessionEndDate {
                        Text("Awake for \(Text(timerInterval: Date.timerRange(until: end), countsDown: true).monospacedDigit().bold())")
                    } else {
                        Text("Awake until turned off")
                    }
                }
                .font(.callout)

                if module.allowDisplaySleep {
                    Text("Display is allowed to sleep")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Picker("Duration", selection: $module.selectedPreset) {
                    ForEach(AwakePreset.allCases) { preset in
                        Text(preset.label).tag(preset)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
        }
    }
}

struct AwakeToggle: View {
    @Bindable var module: AwakeModule

    var body: some View {
        Toggle("Keep Awake", isOn: Binding(
            get: { module.isActive },
            set: { $0 ? module.start() : module.stop() }
        ))
        .labelsHidden()
        .toggleStyle(.switch)
        .controlSize(.small)
    }
}
