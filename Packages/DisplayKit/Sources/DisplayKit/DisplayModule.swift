import AppKit
import SwiftUI
import EyrieCore

/// External display brightness over DDC/CI (MonitorControl core, Apple Silicon path).
@MainActor
@Observable
public final class DisplayModule: EyrieModule {
    public let id = "display"
    public let name = "Displays"
    public let symbolName = "sun.max"
    public var isActive: Bool { false }

    struct DisplayState: Identifiable {
        let id: CGDirectDisplayID
        let name: String
        let supportsDDC: Bool
        var brightness: Double // 0...100
    }

    private(set) var displays: [DisplayState] = []
    private(set) var isRefreshing = false

    public init() {
        refresh()
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true

        let externals = NSScreen.screens.compactMap { screen -> (id: CGDirectDisplayID, name: String)? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            let displayID = CGDirectDisplayID(number.uint32Value)
            guard CGDisplayIsBuiltin(displayID) == 0 else { return nil }
            return (displayID, screen.localizedName)
        }

        Task {
            let infos = await DDCService.shared.refresh(displays: externals)
            displays = infos.map {
                DisplayState(id: $0.id, name: $0.name, supportsDDC: $0.supportsDDC, brightness: Double($0.brightnessPercent))
            }
            isRefreshing = false
        }
    }

    func setBrightness(_ value: Double, for displayID: CGDirectDisplayID) {
        guard let index = displays.firstIndex(where: { $0.id == displayID }) else { return }
        displays[index].brightness = value
        let percent = Int(value.rounded())
        Task {
            await DDCService.shared.setBrightnessPercent(percent, display: displayID)
        }
    }

    public var panelContent: AnyView { AnyView(DisplayPanelView(module: self)) }
}
