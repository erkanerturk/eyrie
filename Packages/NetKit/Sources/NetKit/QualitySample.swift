import EyrieCore
import Foundation

/// One quality tick: round-trip times to the default gateway and a public
/// anchor (1.1.1.1). nil latency = timeout = loss.
public struct QualitySample: Sendable, Equatable, Identifiable {
    public let id: Int
    public var gatewayLatency: TimeInterval?
    public var internetLatency: TimeInterval?

    public init(id: Int, gatewayLatency: TimeInterval? = nil, internetLatency: TimeInterval? = nil) {
        self.id = id
        self.gatewayLatency = gatewayLatency
        self.internetLatency = internetLatency
    }
}

public enum PingStats {
    /// Median of the successful round trips; nil when none succeeded.
    public static func medianLatency(_ latencies: [TimeInterval?]) -> TimeInterval? {
        let successes = latencies.compactMap(\.self).sorted()
        guard !successes.isEmpty else { return nil }
        let middle = successes.count / 2
        if successes.count.isMultiple(of: 2) {
            return (successes[middle - 1] + successes[middle]) / 2
        }
        return successes[middle]
    }

    /// Fraction of attempts that got no reply; nil when nothing was attempted.
    public static func lossFraction(_ latencies: [TimeInterval?]) -> Double? {
        guard !latencies.isEmpty else { return nil }
        let lost = latencies.count(where: { $0 == nil })
        return Double(lost) / Double(latencies.count)
    }
}

/// Pure: turns a sample window into the app-wide status vocabulary, so the
/// quality dot means the same thing as every other dot in the app.
public enum QualityVerdict {
    public static let cautionLatency: TimeInterval = 0.100
    public static let criticalLatency: TimeInterval = 0.200
    public static let cautionLoss = 0.05
    public static let criticalLoss = 0.20

    public static func tone(for samples: [QualitySample]) -> StatusTone {
        guard !samples.isEmpty else { return .inactive }
        let internet = samples.map(\.internetLatency)
        let loss = PingStats.lossFraction(internet) ?? 0
        // Fall back to the gateway when the internet anchor is unreachable —
        // a dead 1.1.1.1 with a healthy gateway is still a real problem, so
        // loss alone decides in that case.
        let median = PingStats.medianLatency(internet)
            ?? PingStats.medianLatency(samples.map(\.gatewayLatency))

        if loss >= criticalLoss { return .critical }
        if let median, median >= criticalLatency { return .critical }
        if loss >= cautionLoss { return .caution }
        if let median, median >= cautionLatency { return .caution }
        return .normal
    }
}
