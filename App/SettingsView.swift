import SwiftUI
import EyrieCore
import ServiceManagement

struct SettingsView: View {
    var registry: ModuleRegistry
    @State private var selection: String? = "general"

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("General", systemImage: "gearshape")
                    .tag("general")
                ForEach(registry.modules, id: \.id) { module in
                    Label(module.name, systemImage: module.symbolName)
                        .tag(module.id)
                }
                Label("About", systemImage: "info.circle")
                    .tag("about")
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detailContent
                .navigationTitle(selectionTitle)
        }
        .frame(width: 640, height: 420)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selection {
        case "general", nil:
            GeneralSettingsView(registry: registry)
        case "about":
            AboutSettingsView()
        default:
            if let module = registry.modules.first(where: { $0.id == selection }) {
                module.settingsContent
            } else {
                GeneralSettingsView(registry: registry)
            }
        }
    }

    private var selectionTitle: String {
        switch selection {
        case "general", nil: "General"
        case "about": "About"
        default: registry.modules.first(where: { $0.id == selection })?.name ?? "Settings"
        }
    }
}

private struct GeneralSettingsView: View {
    var registry: ModuleRegistry
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
            Section("Modules") {
                ForEach(registry.modules, id: \.id) { module in
                    Toggle(isOn: Binding(
                        get: { registry.isEnabled(module) },
                        set: { registry.setEnabled($0, for: module) }
                    )) {
                        Label(module.name, systemImage: module.symbolName)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
