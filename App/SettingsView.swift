import SwiftUI
import EyrieCore
import ServiceManagement

struct SettingsView: View {
    var registry: ModuleRegistry

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsView(registry: registry)
            }
            ForEach(registry.modules, id: \.id) { module in
                Tab(module.name, systemImage: module.symbolName) {
                    module.settingsContent
                }
            }
            Tab("About", systemImage: "info.circle") {
                AboutSettingsView()
            }
        }
        .frame(width: 440, height: 320)
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
