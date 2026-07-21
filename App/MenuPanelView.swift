import SwiftUI
import EyrieCore

/// Content of the menu bar window: one Liquid Glass card per enabled module.
struct MenuPanelView: View {
    var registry: ModuleRegistry
    @Environment(\.openSettings) private var openSettings
    @State private var maxScrollHeight: CGFloat = MenuPanelView.availableScrollHeight()
    @State private var contentHeight: CGFloat = 0
    @State private var showScrollHint = false
    /// One-time cue that the panel scrolls; the indicators are hidden, so a
    /// first-run user has no other way to learn there is more below.
    @AppStorage("panel.scrollHintSeen") private var scrollHintSeen = false

    var body: some View {
        VStack(spacing: 10) {
            header

            ScrollView {
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
                    // Keep the cards' glass edges off the clipping scroll bounds.
                    .padding(.horizontal, 2)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                }
            }
            // The menu bar window sizes itself to the content's ideal height, and
            // a ScrollView's ideal height is its whole content — so a maxHeight
            // alone never kicks in. Pin an exact height instead.
            .frame(height: min(contentHeight, maxScrollHeight))
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.never)
            .overlay(alignment: .bottom) {
                if showScrollHint {
                    ScrollHintBadge()
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .onScrollPhaseChange { _, phase in
                if phase != .idle { dismissScrollHint() }
            }
            .task(id: isScrollable) {
                guard isScrollable, !scrollHintSeen else { return }
                scrollHintSeen = true
                withAnimation(.easeIn(duration: 0.25)) { showScrollHint = true }
                // Task cancellation (panel closed) makes the sleep return early,
                // which is exactly when the hint should disappear too.
                try? await Task.sleep(for: .seconds(4))
                dismissScrollHint()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
                maxScrollHeight = Self.availableScrollHeight()
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

    private var isScrollable: Bool {
        contentHeight > maxScrollHeight + 1
    }

    private func dismissScrollHint() {
        guard showScrollHint else { return }
        withAnimation(.easeOut(duration: 0.3)) { showScrollHint = false }
    }

    /// Upper bound for the scrolling card list. `visibleFrame` already excludes
    /// the menu bar and the Dock; the constant covers what surrounds the scroll
    /// view inside the window (panel padding, header, the gap under the menu bar
    /// and the window shadow).
    private static func availableScrollHeight() -> CGFloat {
        let visible = NSScreen.main?.visibleFrame.height ?? 800
        return max(240, visible - 96)
    }
}

/// Shown once, on the first launch where the panel overflows: a full-width blur
/// that fades the bottom edge out, with a bobbing chevron riding on top of it.
private struct ScrollHintBadge: View {
    @State private var bobbing = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.35), location: 0.45),
                            .init(color: .black, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                // Tall enough to veil several cards, so the cue reads as "there
                // is more below" rather than an edge treatment.
                .frame(height: 400)
                .overlay {
                    VStack(spacing: 8) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.primary)
                            .frame(width: 30, height: 30)
                            .glassEffect(.regular, in: .circle)
                            .offset(y: bobbing ? 4 : -4)
                            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: bobbing)
                        Text("Scroll for more")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
        }
        .frame(maxWidth: .infinity)
        .onAppear { bobbing = true }
    }
}
