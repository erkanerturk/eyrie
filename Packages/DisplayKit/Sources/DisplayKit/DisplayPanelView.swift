import SwiftUI
import EyrieCore

struct DisplayPanelView: View {
    @Bindable var module: DisplayModule

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if module.displays.isEmpty {
                Text(module.isRefreshing ? "Looking for displays…" : "No external displays connected")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(module.displays) { display in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(display.name)
                                .font(.callout)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text("\(Int(display.brightness))%")
                                .font(.callout)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { display.brightness },
                                set: { module.setBrightness($0, for: display.id) }
                            ),
                            in: 0...100,
                            step: 5
                        ) {
                            EmptyView()
                        } minimumValueLabel: {
                            Image(systemName: "sun.min").font(.caption)
                        } maximumValueLabel: {
                            Image(systemName: "sun.max").font(.caption)
                        }
                        .controlSize(.small)
                        .disabled(!display.supportsDDC)

                        if !display.supportsDDC {
                            Text("This display does not respond to DDC/CI")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .onAppear { module.refresh() }
    }
}
