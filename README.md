# Eyrie

[![CI](https://github.com/erkanerturk/eyrie/actions/workflows/ci.yml/badge.svg)](https://github.com/erkanerturk/eyrie/actions/workflows/ci.yml)
![macOS 26+](https://img.shields.io/badge/macOS-26%2B-blue)
![Swift 6](https://img.shields.io/badge/Swift-6-orange)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Latest release](https://img.shields.io/github/v/release/erkanerturk/eyrie)](https://github.com/erkanerturk/eyrie/releases)

A modular macOS menu bar app built with SwiftUI and the macOS 26 (Tahoe) **Liquid Glass** design language. Eyrie bundles the core features of four popular utilities into a single menu bar panel, one module each:

| Module | What it does |
|---|---|
| **Keep Awake** (`AwakeKit`) | Prevents your Mac from sleeping — indefinitely or for a set duration, with optional display sleep |
| **Focus** (`FocusKit`) | Pomodoro timer with focus/break cycles, notifications, and a daily session counter |
| **Audio Share** (`AudioShareKit`) | Plays audio on multiple Bluetooth devices simultaneously with per-device volume |
| **Displays** (`DisplayKit`) | Controls external display brightness over DDC/CI |

## Install

Download the latest `Eyrie-<version>.dmg` from [Releases](https://github.com/erkanerturk/eyrie/releases), open it, and drag **Eyrie** into **Applications**.

> Eyrie is ad-hoc signed (not notarized), so macOS will warn on first launch: right-click the app → **Open**, or clear the quarantine flag with
> `xattr -dr com.apple.quarantine /Applications/Eyrie.app`

Or build from source (see [Building](#building)) and package your own DMG with `./Scripts/make-dmg.sh`.

## Requirements

- **macOS 26 (Tahoe) or later** — the UI uses native Liquid Glass APIs (`glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)`) with no fallback path
- **Apple Silicon** — DisplayKit's DDC/CI path uses the Apple Silicon `IOAVService` route only (no Intel support)
- Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Building

The `.xcodeproj` is **generated, never edited by hand** (it's gitignored). Regenerate it after any change to `project.yml` or when adding files outside existing source directories:

```bash
xcodegen generate
```

Build and run from Xcode, or from the command line:

```bash
xcodebuild -project Eyrie.xcodeproj -scheme Eyrie -configuration Debug build
```

> If `xcode-select` points at the Command Line Tools on your machine, prefix with `DEVELOPER_DIR=/Applications/Xcode.app`, or fix it once with `sudo xcode-select -s /Applications/Xcode.app`.

For fast iteration on a single module, each package builds standalone:

```bash
cd Packages/FocusKit && swift build
```

## Architecture

Every feature is a **local Swift Package**. The app target contains only the shell (menu bar scene, module registry, settings window) and talks to features exclusively through the `EyrieModule` protocol defined in `EyrieCore`.

```
eyrie/
├── project.yml                 # XcodeGen project definition (source of truth)
├── App/                        # App shell — no feature logic here
│   ├── EyrieApp.swift          # @main, MenuBarExtra(.window) + Settings scene + AppDelegate
│   ├── ModuleRegistry.swift    # Owns module instances, enable/disable persistence
│   ├── MenuPanelView.swift     # The glass panel: one ModuleCard per enabled module
│   └── SettingsView.swift      # General tab (launch at login, module toggles) + per-module tabs
└── Packages/
    ├── EyrieCore/              # Protocol + shared services + shared glass UI
    ├── AwakeKit/
    ├── FocusKit/
    ├── AudioShareKit/
    └── DisplayKit/
```

### The module contract

`EyrieCore` defines the protocol every module implements ([EyrieModule.swift](Packages/EyrieCore/Sources/EyrieCore/EyrieModule.swift)):

```swift
@MainActor
public protocol EyrieModule: AnyObject, Identifiable, Observable {
    var id: String { get }              // stable, used as persistence key
    var name: String { get }
    var symbolName: String { get }      // SF Symbol; may change with state
    var isActive: Bool { get }          // drives the menu bar icon (bird → bird.fill)
    var panelContent: AnyView { get }   // the module's section in the panel
    var panelAccessory: AnyView { get } // optional header control (default: empty)
    var settingsContent: AnyView { get }// settings tab (default: "No settings yet")
    func shutdown()                     // undo system-level changes on quit (default: no-op)
}
```

Modules are `@Observable` classes; views observe them directly, so `isActive` flips propagate to the menu bar icon and card headers automatically.

### Shared services (`EyrieCore`)

- **`PowerAssertionService`** — single owner of IOKit power assertions (`IOPMAssertionCreateWithName`). Token-based, so AwakeKit and FocusKit ("keep awake during focus") can hold assertions independently without stepping on each other.
- **`NotificationService`** — `UNUserNotificationCenter` wrapper; requests authorization lazily on first send.
- **`ModuleCard` / `GlassIconButton`** — the shared Liquid Glass visual language. All module panels render inside a `ModuleCard`, so new modules look native for free.

### Adding a new module

1. Create `Packages/YourKit` (copy an existing `Package.swift`, depend on `EyrieCore`).
2. Implement a `@MainActor @Observable final class YourModule: EyrieModule`.
3. Register it in two places:
   - `project.yml` → `packages:` and the target's `dependencies:`
   - [App/ModuleRegistry.swift](App/ModuleRegistry.swift) → append to the `modules` array (plus the `import`)
4. `xcodegen generate` and build.

That's the entire integration surface. Enable/disable, the settings tab, panel card, and shutdown handling all come from the registry and protocol defaults.

## Per-module implementation notes

### AwakeKit
Thin state machine over `PowerAssertionService`. The "allow display sleep" setting picks between `kIOPMAssertionTypePreventUserIdleSystemSleep` and `...PreventUserIdleDisplaySleep`. Timed sessions use a `Task.sleep` and release the assertion + notify on expiry.

**Verify:** toggle it on, then `pmset -g assertions | grep Eyrie`.

### FocusKit
Pomodoro state machine: focus → short break, long break after every N focus sessions (`sessionsBeforeLongBreak`). A naturally finished phase parks in a *pending* state (`pendingPhase`) until the user starts the next one; only an explicit skip enters the next phase immediately. Pausing captures remaining seconds and cancels the phase task; resuming reschedules. The daily counter persists in `UserDefaults` keyed by ISO date.

### AudioShareKit
All CoreAudio access lives in [CoreAudioSupport.swift](Packages/AudioShareKit/Sources/AudioShareKit/CoreAudioSupport.swift). Sharing creates a **stacked aggregate device** (`AudioHardwareCreateAggregateDevice` with `kAudioAggregateDeviceIsStackedKey`) from the selected device UIDs. The first device is the master clock; every other sub-device gets `kAudioSubDeviceDriftCompensationKey` so sample-rate drift doesn't cause pitch shift. The previous default output is remembered and restored on stop, and `shutdown()` tears the aggregate down on quit (the `AppDelegate` calls it). A device-list listener rebuilds or stops sharing when a participating device disappears (e.g. AirPods back in the case).

**Verify:** with sharing on, the "Eyrie Audio Share" device appears in Audio MIDI Setup and is the default output; it disappears on stop.

### DisplayKit — ⚠️ private APIs
Uses the same Apple Silicon route as MonitorControl/m1ddc: `DCPAVServiceProxy` IORegistry entries → `IOAVServiceCreateWithService` → raw DDC/CI packets via `IOAVServiceWriteI2C`/`ReadI2C` (declared with `@_silgen_name` in [DDCService.swift](Packages/DisplayKit/Sources/DisplayKit/DDCService.swift)). Displays are matched to services by comparing `CGDisplayCreateUUIDFromDisplayID` against the service's `EDID UUID` property, with a 1:1 fallback when exactly one of each is unmatched. All I2C traffic is serialized through the `DDCService` actor. Brightness is VCP code `0x10`; the max value is learned from the first successful read (assumed 100 if the monitor rejects reads).

**These are private, unsupported APIs.** They can break on any macOS update and are the reason Eyrie targets **direct distribution only** — this app cannot ship on the App Store, and the sandbox is disabled in `project.yml`.

## Constraints & conventions for contributors

- **Don't edit `Eyrie.xcodeproj`** — change `project.yml` and regenerate.
- **No sandbox, no App Store.** If you add a feature, you may use non-sandbox APIs, but keep anything private-API-shaped isolated in its own package like DisplayKit does.
- **Swift 6 strict concurrency** is on. Modules are `@MainActor`; anything that talks to hardware slowly or serially (DDC) belongs in an actor; C callbacks must hop back explicitly.
- **UI language is English**; user-visible strings live next to their views for now (no localization yet).
- **Persistence** is plain `UserDefaults` with `<moduleID>.<key>` naming (e.g. `focus.dailyCount`, `audioshare.selected`).
- A module must leave the system clean: implement `shutdown()` if you touch anything outside the process (assertions, audio topology, display state).
