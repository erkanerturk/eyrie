import Foundation

/// Cumulative host CPU ticks since boot, per `HOST_CPU_LOAD_INFO`.
/// The counters wrap around `UInt32.max`; consumers must diff with `&-`.
public struct CPUTicks: Sendable, Equatable {
    public var user: UInt32
    public var system: UInt32
    public var idle: UInt32
    public var nice: UInt32

    public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }
}

/// Kernel memory pressure, per `kern.memorystatus_vm_pressure_level`
/// (dispatch memorypressure levels: 1 / 2 / 4).
public enum MemoryPressureLevel: Int, Sendable, Equatable {
    case normal = 1
    case warning = 2
    case critical = 4
}

/// One raw reading of cumulative system counters. Rates are derived by
/// diffing two of these in `MetricsMath`, never stored here.
public struct RawMetricsSample: Sendable, Equatable {
    /// Monotonic clock (CLOCK_MONOTONIC_RAW) in seconds — never wall-clock,
    /// which can jump under NTP and break rate math.
    public var uptime: TimeInterval
    public var cpu: CPUTicks
    public var memoryUsedBytes: UInt64
    public var memoryTotalBytes: UInt64
    /// Nil when the pressure sysctl is unavailable.
    public var memoryPressure: MemoryPressureLevel?
    /// Sum across all non-loopback, up-and-running interfaces. Not guaranteed
    /// monotonic: an interface disappearing (VPN utun) shrinks the sum.
    public var networkBytesReceived: UInt64
    public var networkBytesSent: UInt64

    public init(
        uptime: TimeInterval,
        cpu: CPUTicks,
        memoryUsedBytes: UInt64,
        memoryTotalBytes: UInt64,
        memoryPressure: MemoryPressureLevel? = nil,
        networkBytesReceived: UInt64,
        networkBytesSent: UInt64
    ) {
        self.uptime = uptime
        self.cpu = cpu
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryTotalBytes = memoryTotalBytes
        self.memoryPressure = memoryPressure
        self.networkBytesReceived = networkBytesReceived
        self.networkBytesSent = networkBytesSent
    }
}

/// A derived, display-ready reading. Rate fields are nil until a second raw
/// sample exists (and after any rebaseline: sleep/wake, counter regression).
public struct MetricsSnapshot: Sendable, Equatable, Identifiable {
    /// Monotonically increasing tick index — stable identity for Charts.
    public let id: Int
    public var cpuTotal: Double?
    public var cpuUser: Double?
    public var cpuSystem: Double?
    public var memoryUsedBytes: UInt64
    public var memoryTotalBytes: UInt64
    public var memoryPressure: MemoryPressureLevel?
    public var downBytesPerSecond: Double?
    public var upBytesPerSecond: Double?

    public var memoryFraction: Double {
        memoryTotalBytes == 0 ? 0 : Double(memoryUsedBytes) / Double(memoryTotalBytes)
    }
}

public protocol SystemMetricsProviding: Sendable {
    func sample() throws -> RawMetricsSample
}

/// Pure delta math from raw cumulative counters to display rates.
/// All first-sample / wraparound / rebaseline decisions live here.
enum MetricsMath {
    /// Rates are dropped (nil) when the elapsed time is implausible: a gap
    /// this large means the Mac slept or the loop stalled, and averaging
    /// across it would be misleading.
    static let maxElapsedFactor: Double = 3
    static let minElapsed: TimeInterval = 0.05

    static func snapshot(
        id: Int,
        previous: RawMetricsSample?,
        current: RawMetricsSample,
        interval: TimeInterval
    ) -> MetricsSnapshot {
        var snapshot = MetricsSnapshot(
            id: id,
            cpuTotal: nil,
            cpuUser: nil,
            cpuSystem: nil,
            memoryUsedBytes: current.memoryUsedBytes,
            memoryTotalBytes: current.memoryTotalBytes,
            memoryPressure: current.memoryPressure,
            downBytesPerSecond: nil,
            upBytesPerSecond: nil
        )

        guard let previous else { return snapshot }

        let elapsed = current.uptime - previous.uptime
        guard elapsed >= minElapsed, elapsed <= interval * maxElapsedFactor else {
            return snapshot
        }

        // CPU ticks accumulate; a single UInt32 wrap is handled by `&-`.
        let user = current.cpu.user &- previous.cpu.user
        let system = current.cpu.system &- previous.cpu.system
        let idle = current.cpu.idle &- previous.cpu.idle
        let nice = current.cpu.nice &- previous.cpu.nice
        let busy = UInt64(user) + UInt64(system) + UInt64(nice)
        let total = busy + UInt64(idle)
        if total > 0 {
            snapshot.cpuTotal = Double(busy) / Double(total)
            snapshot.cpuUser = Double(UInt64(user) + UInt64(nice)) / Double(total)
            snapshot.cpuSystem = Double(system) / Double(total)
        }

        // The interface sum can legitimately shrink; treat regression as a
        // rebaseline tick rather than reporting an absurd rate.
        if current.networkBytesReceived >= previous.networkBytesReceived,
           current.networkBytesSent >= previous.networkBytesSent {
            snapshot.downBytesPerSecond =
                Double(current.networkBytesReceived - previous.networkBytesReceived) / elapsed
            snapshot.upBytesPerSecond =
                Double(current.networkBytesSent - previous.networkBytesSent) / elapsed
        }

        return snapshot
    }
}
