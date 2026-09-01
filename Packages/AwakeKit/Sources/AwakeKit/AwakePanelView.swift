import SwiftUI
import EyrieCore

struct AwakePanelView: View {
    @Bindable var module: AwakeModule

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .leading) {
                // The picker stays in the layout while a session is active so the
                // card keeps a constant height; the status line renders on top.
                Picker("Duration", selection: $module.selectedPreset) {
                    ForEach(AwakePreset.allCases) { preset in
                        Text(preset.label).tag(preset)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .opacity(module.isSessionActive ? 0 : 1)
                .allowsHitTesting(!module.isSessionActive)
                .accessibilityHidden(module.isSessionActive)

                if module.isSessionActive {
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
                }
            }

            if module.allowDisplaySleep {
                Text(module.isSessionActive ? "Display is allowed to sleep" : "Display will be allowed to sleep")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Same row shape as the card header (label, Spacer, bare switch)
            // so this switch shares the header toggle's trailing column.
            HStack {
                Text("Simulate activity")
                Spacer(minLength: 0)
                Toggle("Simulate activity", isOn: $module.simulateActivity)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            if module.simulateActivity, !module.hasAccessibilityTrust {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    StatusDot(.caution)
                    Text("Needs Accessibility access — allow Eyrie in System Settings → Privacy & Security → Accessibility.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

struct AwakeToggle: View {
    @Bindable var module: AwakeModule

    var body: some View {
        Toggle("Keep Awake", isOn: Binding(
            get: { module.isSessionActive },
            set: { $0 ? module.start() : module.stop() }
        ))
        .labelsHidden()
        .toggleStyle(.switch)
        .controlSize(.small)
    }
}
