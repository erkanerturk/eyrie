import SwiftUI
import EyrieCore

/// Content of the menu bar window: one Liquid Glass card per enabled module.
struct MenuPanelView: View {
    var registry: ModuleRegistry
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 10) {
            header

            GlassEffectContainer(spacing: 10) {
                VStack(spacing: 10) {
                    ForEach(registry.enabledModules, id: \.id) { module in
                        ModuleCard(
                            title: module.name,
                            symbolName: module.symbolName,
                            isActive: module.isActive
                        ) {
                            module.panelContent
                        } accessory: {
                            module.panelAccessory
                        }
                    }
                }
            }

            if registry.enabledModules.isEmpty {
                Text("All modules are turned off.\nEnable them in Settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 20)
            }
        }
        .padding(12)
        .frame(width: 340)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Eyrie")
                .font(.title3.weight(.semibold))
            Spacer()
            GlassIconButton(symbolName: "gearshape") {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            }
            GlassIconButton(symbolName: "power") {
                NSApp.terminate(nil)
            }
        }
        .padding(.horizontal, 4)
    }
}
