import SwiftUI

/// Contract every Eyrie feature module implements. The app target only talks
/// to modules through this protocol, so adding a feature means adding a new
/// package and one registry entry.
@MainActor
public protocol EyrieModule: AnyObject, Identifiable, Observable {
    /// Stable identifier, also used as the persistence key for enable/disable.
    var id: String { get }
    var name: String { get }
    /// SF Symbol shown in the panel card and settings.
    var symbolName: String { get }
    /// Whether the module is currently doing something (drives the menu bar icon state).
    var isActive: Bool { get }
    /// The module's section in the menu bar panel.
    var panelContent: AnyView { get }
    /// Optional control shown in the module card's header (e.g. an on/off toggle).
    var panelAccessory: AnyView { get }
    /// The module's tab in the settings window.
    var settingsContent: AnyView { get }
    /// Called when the app is about to terminate so the module can undo
    /// system-level changes (power assertions, aggregate audio devices, ...).
    func shutdown()
    /// Called at launch with the persisted state and whenever the user toggles
    /// the module in Settings. A disabled module is still instantiated, so any
    /// module that works outside the panel must stop doing so here.
    func setModuleEnabled(_ enabled: Bool)
}

public extension EyrieModule {
    func shutdown() {}

    /// Panel-driven modules need nothing beyond this: a disabled module is
    /// never rendered, so its `onDisappear` teardown has already run.
    func setModuleEnabled(_ enabled: Bool) {
        if !enabled { shutdown() }
    }

    var panelAccessory: AnyView { AnyView(EmptyView()) }

    var settingsContent: AnyView {
        AnyView(
            Text("No settings yet")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
    }
}
