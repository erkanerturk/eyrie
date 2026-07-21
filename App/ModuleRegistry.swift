import SwiftUI
import EyrieCore
import AwakeKit
import FocusKit
import DisplayKit
import AudioShareKit
import StatsKit
import NetKit
import TrafficKit

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
    private static let knownKey = "registry.knownModules"
    /// Modules that shipped before `registry.knownModules` existed. An install
    /// upgrading from such a build must not have deliberate disables of these
    /// treated as "newly added" and re-enabled.
    private static let legacyKnownIDs = ["awake", "focus", "audioshare", "display", "stats", "net"]

    init() {
        modules = [
            AwakeModule(),
            FocusModule(),
            DisplayModule(),
            AudioShareModule(),
            StatsModule(),
            NetModule(),
            TrafficModule(),
        ]
        let defaults = UserDefaults.standard
        let currentIDs = modules.map(\.id)
        if let stored = defaults.stringArray(forKey: Self.enabledKey) {
            // A module added in an update is absent from the stored enabled
            // set; enable it once, without resurrecting known-but-disabled ones.
            let known = defaults.stringArray(forKey: Self.knownKey) ?? Self.legacyKnownIDs
            enabledIDs = Set(stored).union(currentIDs.filter { !known.contains($0) })
        } else {
            enabledIDs = Set(currentIDs)
        }
        // Property assignment in init doesn't fire didSet — persist explicitly.
        defaults.set(Array(enabledIDs), forKey: Self.enabledKey)
        defaults.set(currentIDs, forKey: Self.knownKey)
        // Every module is instantiated regardless; this is what stops a
        // disabled one from doing background work.
        for module in modules {
            module.setModuleEnabled(enabledIDs.contains(module.id))
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
        module.setModuleEnabled(enabled)
    }
}
