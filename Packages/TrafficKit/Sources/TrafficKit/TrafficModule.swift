import AppKit
import EyrieCore
import SwiftUI
import os

/// Traffic card: top per-app consumers (nettop), interface totals since boot,
/// and a persisted per-day tally. Sampling runs only while the panel is on
/// screen; the optional background tracking is a single cheap sysctl read on a
/// user-chosen interval, clearly opt-in from Settings.
@MainActor
@Observable
public final class TrafficModule: EyrieModule {
    public let id = "traffic"
    public let name = "Traffic"
    public let symbolName = "arrow.up.arrow.down"
    /// Passive observer — must never flip the menu bar icon to active.
    public var isActive: Bool { false }

    /// Already sorted and capped for display; nil until the first sample.
    public private(set) var topConsumers: [ProcessTrafficRate]?
    /// nettop missing, failed, or its output format drifted.
    public private(set) var perAppUnavailable = false
    public private(set) var sessionReceived: UInt64?
    public private(set) var sessionSent: UInt64?
    public let usageStore: DailyUsageStore

    public var showPerApp: Bool {
        didSet {
            defaults.set(showPerApp, forKey: Self.showPerAppKey)
            if !showPerApp {
                topConsumers = nil
                perAppUnavailable = false
                previousFrame = nil
                previousFrameAt = nil
            }
        }
    }
    public var topCount: Int {
        didSet {
            defaults.set(topCount, forKey: Self.topCountKey)
            recomputeTopConsumers()
        }
    }
    public var backgroundTracking: Bool {
        didSet {
            defaults.set(backgroundTracking, forKey: Self.backgroundTrackingKey)
            syncBackgroundLoop()
        }
    }
    /// Minutes between background counter readings.
    public var backgroundIntervalMinutes: Int {
        didSet {
            defaults.set(backgroundIntervalMinutes, forKey: Self.backgroundIntervalKey)
            syncBackgroundLoop()
        }
    }

    @ObservationIgnored private let sampler: any ProcessTrafficSampling
    @ObservationIgnored private let readCounters: @Sendable () throws -> [InterfaceCounters]
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var backgroundTask: Task<Void, Never>?
    /// The registry pins this right after init; assume enabled until told.
    @ObservationIgnored private var isModuleEnabled = true
    @ObservationIgnored private var latestRates: [ProcessTrafficRate] = []
    @ObservationIgnored private var previousFrame: [ProcessTraffic]?
    @ObservationIgnored private var previousFrameAt: Date?
    /// pid → localized app name. Resolving this per row per render made the
    /// panel do workspace lookups on every observable change.
    @ObservationIgnored private var displayNames: [Int32: String] = [:]
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let logger = Logger(subsystem: "com.erkanerturk.eyrie", category: "Traffic")

    private static let showPerAppKey = "traffic.showPerApp"
    private static let topCountKey = "traffic.topCount"
    private static let backgroundTrackingKey = "traffic.backgroundTracking"
    private static let backgroundIntervalKey = "traffic.backgroundInterval"
    static let tickInterval: TimeInterval = 2
    public static let backgroundIntervalChoices = [5, 10, 20]

    public init(
        sampler: any ProcessTrafficSampling = LiveNettopSampler(),
        readCounters: @escaping @Sendable () throws -> [InterfaceCounters] = { try NetworkInterfaceCounters.read() },
        usageStore: DailyUsageStore? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.sampler = sampler
        self.readCounters = readCounters
        self.usageStore = usageStore ?? DailyUsageStore()
        self.now = now
        showPerApp = defaults.object(forKey: Self.showPerAppKey) as? Bool ?? true
        topCount = defaults.object(forKey: Self.topCountKey) as? Int ?? 5
        backgroundTracking = defaults.object(forKey: Self.backgroundTrackingKey) as? Bool ?? false
        backgroundIntervalMinutes = defaults.object(forKey: Self.backgroundIntervalKey) as? Int ?? 20
        syncBackgroundLoop()
    }

    /// Idempotent; called from the panel's onAppear. One loop drives both the
    /// interface counters and the per-app sample.
    func begin() {
        guard tickTask == nil else { return }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                guard !Task.isCancelled else { return }
                try? await Task.sleep(
                    for: .seconds(Self.tickInterval),
                    tolerance: .seconds(Self.tickInterval * 0.2)
                )
            }
        }
    }

    /// Called from the panel's onDisappear. Also flushes the day tally, which
    /// is only written to disk periodically while running.
    func end() {
        tickTask?.cancel()
        tickTask = nil
        previousFrame = nil
        previousFrameAt = nil
        usageStore.flush()
    }

    public func shutdown() {
        end()
        backgroundTask?.cancel()
        backgroundTask = nil
    }

    /// This is the one module that keeps working with the panel closed, so a
    /// module the user switched off must not keep reading counters.
    public func setModuleEnabled(_ enabled: Bool) {
        isModuleEnabled = enabled
        if !enabled { end() }
        syncBackgroundLoop()
    }

    func tick() async {
        readInterfaceCounters()
        guard showPerApp else { return }
        let frame = await sampler.sample()
        guard !Task.isCancelled else { return }
        applyFrame(frame)
    }

    // MARK: - Per-app

    /// Synchronous state transition, injectable from tests. nil = unavailable.
    func applyFrame(_ frame: [ProcessTraffic]?) {
        guard let frame, !frame.isEmpty else {
            topConsumers = nil
            perAppUnavailable = true
            return
        }
        perAppUnavailable = false
        let elapsed = previousFrameAt.map { now().timeIntervalSince($0) } ?? 0
        latestRates = TrafficMath.rates(
            previous: previousFrame ?? [],
            current: frame,
            elapsed: elapsed
        )
        previousFrame = frame
        previousFrameAt = now()
        recomputeTopConsumers()
    }

    /// Sorting and name resolution happen here, not in the view body.
    private func recomputeTopConsumers() {
        guard !latestRates.isEmpty else { return }
        let top = TrafficMath.topConsumers(latestRates, count: topCount)
        topConsumers = top.map { row in
            var named = row
            named.displayName = resolvedName(for: row)
            return named
        }
    }

    private func resolvedName(for row: ProcessTrafficRate) -> String {
        if let cached = displayNames[row.pid] { return cached }
        // nettop truncates to ~15 characters; the running app has a better one.
        let resolved = NSRunningApplication(processIdentifier: row.pid)?.localizedName ?? row.name
        displayNames[row.pid] = resolved
        return resolved
    }

    // MARK: - Interface totals + daily usage

    func readInterfaceCounters() {
        do {
            let counters = try readCounters()
            let totals = NetworkInterfaceCounters.totals(of: counters)
            // Assign only on change: an identical value still invalidates
            // observers and re-renders the whole panel.
            if sessionReceived != totals.received { sessionReceived = totals.received }
            if sessionSent != totals.sent { sessionSent = totals.sent }
            usageStore.ingest(counters)
        } catch {
            logger.error("Interface counter read failed: \(error)")
        }
    }

    private func syncBackgroundLoop() {
        backgroundTask?.cancel()
        backgroundTask = nil
        guard isModuleEnabled, backgroundTracking else { return }
        let interval = TimeInterval(backgroundIntervalMinutes * 60)
        backgroundTask = Task { [weak self] in
            // Immediate baseline so the first interval's delta is attributable.
            self?.backgroundIngest()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval), tolerance: .seconds(120))
                guard !Task.isCancelled else { return }
                self?.backgroundIngest()
            }
        }
    }

    private func backgroundIngest() {
        guard let counters = try? readCounters() else { return }
        usageStore.ingest(counters)
        usageStore.flush()
    }

    public var panelContent: AnyView { AnyView(TrafficPanelView(module: self)) }
    public var settingsContent: AnyView { AnyView(TrafficSettingsView(module: self)) }
}
