import EyrieCore
import Foundation

public enum FirewallState: Sendable, Equatable {
    case disabled
    case enabled
    /// "Block all incoming connections" mode.
    case blockAll
    case unknown
}

public protocol FirewallStateProviding: Sendable {
    func currentState() async -> FirewallState
}

/// Reads the application firewall state. `socketfilterfw --getglobalstate`
/// works without root and is the same source Activity-style tools use.
public struct LiveFirewallStateProvider: FirewallStateProviding {
    public init() {}

    public func currentState() async -> FirewallState {
        guard let output = try? await ProcessRunner.run(
            "/usr/libexec/ApplicationFirewall/socketfilterfw",
            arguments: ["--getglobalstate"],
            timeout: .seconds(3)
        ) else { return .unknown }
        return FirewallOutputParser.parse(
            status: output.terminationStatus,
            output: output.standardOutput
        )
    }
}

/// Pure: tolerant of wording changes as long as "(State = n)" survives.
public enum FirewallOutputParser {
    public static func parse(status: Int32, output: String) -> FirewallState {
        guard status == 0 else { return .unknown }
        if output.contains("(State = 0)") { return .disabled }
        if output.contains("(State = 1)") { return .enabled }
        if output.contains("(State = 2)") { return .blockAll }
        return .unknown
    }
}
