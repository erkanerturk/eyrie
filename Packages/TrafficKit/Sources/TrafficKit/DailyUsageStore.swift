import EyrieCore
import Foundation

/// Per-day byte totals accumulated from interface counter observations.
/// Deltas are tracked per interface name, so a VPN utun vanishing or a reboot
/// (counter regression → rebaseline to the new value) never corrupts another
/// interface's contribution. A delta spanning midnight is attributed to the
/// day it is observed — a documented approximation, not a bug.
@MainActor
@Observable
public final class DailyUsageStore {
    public private(set) var todayBytesIn: UInt64 = 0
    public private(set) var todayBytesOut: UInt64 = 0

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var daily: [String: DayTotal]
    @ObservationIgnored private var lastCounters: [String: CounterPair]
    @ObservationIgnored private var lastPersistedAt: Date?
    @ObservationIgnored private var isDirty = false

    struct DayTotal: Codable, Equatable {
        var bytesIn: UInt64 = 0
        var bytesOut: UInt64 = 0
    }

    struct CounterPair: Codable, Equatable {
        var bytesIn: UInt64
        var bytesOut: UInt64
    }

    static let dailyKey = "traffic.dailyUsage"
    static let lastCountersKey = "traffic.lastCounters"
    static let retentionDays = 60
    /// In-memory is the source of truth between flushes; encoding + writing
    /// two defaults keys on every tick was pure overhead.
    static let persistInterval: TimeInterval = 30

    public init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        daily = Self.decode([String: DayTotal].self, from: defaults, key: Self.dailyKey) ?? [:]
        lastCounters = Self.decode([String: CounterPair].self, from: defaults, key: Self.lastCountersKey) ?? [:]
        refreshToday()
    }

    public func ingest(_ counters: [InterfaceCounters]) {
        var deltaIn: UInt64 = 0
        var deltaOut: UInt64 = 0
        var seen: [String: CounterPair] = [:]
        for interface in counters where !interface.isLoopback {
            let pair = CounterPair(bytesIn: interface.bytesIn, bytesOut: interface.bytesOut)
            // First sight or regression (reboot / recreated utun): baseline
            // only — the delta starts counting from the next observation.
            if let previous = lastCounters[interface.name],
               previous.bytesIn <= pair.bytesIn, previous.bytesOut <= pair.bytesOut {
                deltaIn &+= pair.bytesIn - previous.bytesIn
                deltaOut &+= pair.bytesOut - previous.bytesOut
            }
            seen[interface.name] = pair
        }
        lastCounters = seen

        let key = Self.dayKey(for: now())
        var day = daily[key] ?? DayTotal()
        day.bytesIn &+= deltaIn
        day.bytesOut &+= deltaOut
        daily[key] = day
        prune()
        isDirty = true
        persistIfDue()
        refreshToday()
    }

    /// Writes pending state to disk. Called on panel close, on background
    /// readings, and periodically from `ingest`.
    public func flush() {
        guard isDirty else { return }
        persist()
    }

    public func total(for day: Date) -> (bytesIn: UInt64, bytesOut: UInt64)? {
        daily[Self.dayKey(for: day)].map { ($0.bytesIn, $0.bytesOut) }
    }

    private func refreshToday() {
        let today = daily[Self.dayKey(for: now())] ?? DayTotal()
        // Assign only on change — an identical value still re-renders the panel.
        if todayBytesIn != today.bytesIn { todayBytesIn = today.bytesIn }
        if todayBytesOut != today.bytesOut { todayBytesOut = today.bytesOut }
    }

    private func persistIfDue() {
        let current = now()
        if let lastPersistedAt, current.timeIntervalSince(lastPersistedAt) < Self.persistInterval {
            return
        }
        persist()
    }

    private func prune() {
        guard daily.count > Self.retentionDays else { return }
        // Keys are yyyy-MM-dd, so lexicographic order is date order.
        for stale in daily.keys.sorted().dropLast(Self.retentionDays) {
            daily.removeValue(forKey: stale)
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(daily) {
            defaults.set(data, forKey: Self.dailyKey)
        }
        if let data = try? JSONEncoder().encode(lastCounters) {
            defaults.set(data, forKey: Self.lastCountersKey)
        }
        lastPersistedAt = now()
        isDirty = false
    }

    private static func decode<Value: Decodable>(
        _ type: Value.Type, from defaults: UserDefaults, key: String
    ) -> Value? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    private static func dayKey(for date: Date) -> String {
        // Local calendar day — "today" must match the user's wall clock.
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
