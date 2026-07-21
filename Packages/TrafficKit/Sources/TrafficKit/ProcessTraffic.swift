import Foundation

/// One process's cumulative byte counters, as nettop reports them.
public struct ProcessTraffic: Sendable, Equatable {
    public var pid: Int32
    /// nettop truncates to ~15 characters; the UI resolves a pretty name via
    /// NSRunningApplication at render time.
    public var name: String
    public var bytesIn: UInt64
    public var bytesOut: UInt64

    public init(pid: Int32, name: String, bytesIn: UInt64, bytesOut: UInt64) {
        self.pid = pid
        self.name = name
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
    }

    public var totalBytes: UInt64 { bytesIn &+ bytesOut }
}

/// Cumulative totals plus the current per-second rates from the last frame pair.
public struct ProcessTrafficRate: Sendable, Equatable, Identifiable {
    public var pid: Int32
    public var name: String
    public var bytesIn: UInt64
    public var bytesOut: UInt64
    public var inPerSecond: Double
    public var outPerSecond: Double
    /// Resolved once by the module (cached workspace lookup), never in a view
    /// body. Falls back to nettop's truncated name.
    public var displayName: String

    public var id: Int32 { pid }
    public var totalBytes: UInt64 { bytesIn &+ bytesOut }

    public init(pid: Int32, name: String, bytesIn: UInt64, bytesOut: UInt64,
                inPerSecond: Double, outPerSecond: Double, displayName: String? = nil) {
        self.pid = pid
        self.name = name
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
        self.inPerSecond = inPerSecond
        self.outPerSecond = outPerSecond
        self.displayName = displayName ?? name
    }
}
