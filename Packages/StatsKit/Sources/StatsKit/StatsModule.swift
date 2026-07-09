import SwiftUI
import EyrieCore
import os

/// Live CPU / memory / network stats (iStat Menus core). Sampling only runs
/// while the panel is on screen, so the module costs nothing when idle.
@MainActor
@Observable
public final class StatsModule: EyrieModule {
    public let id = "stats"
    public let name = "Stats"
    public let symbolName = "gauge.with.dots.needle.50percent"
    /// Passive observer — must never flip the menu bar icon to active.
    public var isActive: Bool { false }

    public private(set) var latest: MetricsSnapshot?
    public private(set) var history = RingBuffer<MetricsSnapshot>(capacity: 60)

    public var samplingInterval: Double {
        didSet { defaults.set(samplingInterval, forKey: Self.intervalKey) }
    }
    public var showCPU: Bool {
        didSet { defaults.set(showCPU, forKey: Self.showCPUKey) }
    }
    public var showMemory: Bool {
        didSet { defaults.set(showMemory, forKey: Self.showMemoryKey) }
    }
    public var showNetwork: Bool {
        didSet { defaults.set(showNetwork, forKey: Self.showNetworkKey) }
    }

    @ObservationIgnored private let provider: any SystemMetricsProviding
    @ObservationIgnored private var samplingTask: Task<Void, Never>?
    @ObservationIgnored private var previousRaw: RawMetricsSample?
    @ObservationIgnored private var tickIndex = 0
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let logger = Logger(subsystem: "com.erkanerturk.eyrie", category: "Stats")

    private static let intervalKey = "stats.samplingInterval"
    private static let showCPUKey = "stats.showCPU"
    private static let showMemoryKey = "stats.showMemory"
    private static let showNetworkKey = "stats.showNetwork"

    public init(provider: any SystemMetricsProviding = LiveSystemMetricsProvider()) {
        self.provider = provider
        samplingInterval = defaults.object(forKey: Self.intervalKey) as? Double ?? 1
        showCPU = defaults.object(forKey: Self.showCPUKey) as? Bool ?? true
        showMemory = defaults.object(forKey: Self.showMemoryKey) as? Bool ?? true
        showNetwork = defaults.object(forKey: Self.showNetworkKey) as? Bool ?? true
    }

    /// Idempotent; called from the panel's onAppear.
    func beginSampling() {
        guard samplingTask == nil else { return }
        tick()
        samplingTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval = self?.samplingInterval ?? 1
                // Generous tolerance lets the system coalesce this wakeup
                // with other timers instead of firing on its own.
                try? await Task.sleep(for: .seconds(interval), tolerance: .seconds(interval * 0.2))
                guard !Task.isCancelled else { return }
                self?.tick()
            }
        }
    }

    /// Called from the panel's onDisappear. Clears the delta baseline so a
    /// stale reading never produces a rate averaged across panel opens.
    func endSampling() {
        samplingTask?.cancel()
        samplingTask = nil
        previousRaw = nil
    }

    func tick() {
        do {
            let raw = try provider.sample()
            let snapshot = MetricsMath.snapshot(
                id: tickIndex,
                previous: previousRaw,
                current: raw,
                interval: samplingInterval
            )
            tickIndex += 1
            previousRaw = raw
            latest = snapshot
            history.append(snapshot)
        } catch {
            logger.error("Metric sample failed: \(error)")
        }
    }

    public var panelContent: AnyView { AnyView(StatsPanelView(module: self)) }
    public var settingsContent: AnyView { AnyView(StatsSettingsView(module: self)) }
}
