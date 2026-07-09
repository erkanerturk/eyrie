import SwiftUI
import EyrieCore
import AwakeKit
import FocusKit
import DisplayKit
import AudioShareKit
import StatsKit
import NetKit

/// Owns all feature modules and which of them are enabled. Adding a module to
/// the app means appending one entry to `modules` here.
@MainActor
@Observable
final class ModuleRegistry {
    let modules: [any EyrieModule]

    private(set) var enabledIDs: Set<String> {
        didSet { UserDefaults.standard.set(Array(enabledIDs), forKey: Self.enabledKey) }
    }

    private static let enabledKey = "registry.enabledModules"

    init() {
        modules = [
            AwakeModule(),
            FocusModule(),
            AudioShareModule(),
            DisplayModule(),
            StatsModule(),
            NetModule(),
        ]
        if let stored = UserDefaults.standard.stringArray(forKey: Self.enabledKey) {
            enabledIDs = Set(stored)
        } else {
            enabledIDs = Set(modules.map(\.id))
        }
    }

    var enabledModules: [any EyrieModule] {
        modules.filter { enabledIDs.contains($0.id) }
    }

    var isAnyModuleActive: Bool {
        enabledModules.contains { $0.isActive }
    }

    var menuBarSymbol: String {
        isAnyModuleActive ? "bird.fill" : "bird"
    }

    func isEnabled(_ module: any EyrieModule) -> Bool {
        enabledIDs.contains(module.id)
    }

    func setEnabled(_ enabled: Bool, for module: any EyrieModule) {
        if enabled {
            enabledIDs.insert(module.id)
        } else {
            enabledIDs.remove(module.id)
        }
    }
}
