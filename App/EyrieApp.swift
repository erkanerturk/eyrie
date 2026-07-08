import SwiftUI
import EyrieCore

@main
struct EyrieApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var registry: ModuleRegistry

    init() {
        let registry = ModuleRegistry()
        _registry = State(initialValue: registry)
        AppDelegate.registry = registry
    }

    var body: some Scene {
        MenuBarExtra {
            MenuPanelView(registry: registry)
        } label: {
            Image(systemName: registry.menuBarSymbol)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(registry: registry)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var registry: ModuleRegistry?

    func applicationWillTerminate(_ notification: Notification) {
        Self.registry?.modules.forEach { $0.shutdown() }
        PowerAssertionService.shared.releaseAll()
    }
}
