import Foundation

/// What kind of link the current default path uses.
public enum ConnectionKind: Sendable, Equatable {
    case wifi
    case ethernet
    /// Satisfied path over anything else (VPN/utun, cellular hotspot bridge…).
    case other
    case offline

    public var label: String {
        switch self {
        case .wifi: "Wi-Fi"
        case .ethernet: "Ethernet"
        case .other: "Connected"
        case .offline: "Offline"
        }
    }

    public var symbolName: String {
        switch self {
        case .wifi: "wifi"
        case .ethernet: "cable.connector"
        case .other: "network"
        case .offline: "wifi.slash"
        }
    }
}

/// Sendable value emitted by the path monitor. `NWPath` itself never crosses
/// the concurrency boundary.
public struct NetworkSnapshot: Sendable, Equatable {
    public var kind: ConnectionKind
    public var interfaceName: String?
    public var localIPv4: String?
    public var localIPv6: String?

    public init(kind: ConnectionKind, interfaceName: String? = nil,
                localIPv4: String? = nil, localIPv6: String? = nil) {
        self.kind = kind
        self.interfaceName = interfaceName
        self.localIPv4 = localIPv4
        self.localIPv6 = localIPv6
    }

    /// The address the panel shows: IPv4 preferred, IPv6 fallback.
    public var displayLocalIP: String? { localIPv4 ?? localIPv6 }

    /// Two snapshots on the same network identity share the external IP cache;
    /// a change here invalidates it.
    public func sameNetworkIdentity(as other: NetworkSnapshot) -> Bool {
        kind == other.kind && interfaceName == other.interfaceName
    }
}

/// One address record from `getifaddrs`, reduced to what the filter needs.
public struct InterfaceAddress: Sendable, Equatable {
    public var name: String
    public var isIPv6: Bool
    public var address: String
    public var isUp: Bool
    public var isRunning: Bool
    public var isLoopback: Bool

    public init(name: String, isIPv6: Bool, address: String,
                isUp: Bool, isRunning: Bool, isLoopback: Bool) {
        self.name = name
        self.isIPv6 = isIPv6
        self.address = address
        self.isUp = isUp
        self.isRunning = isRunning
        self.isLoopback = isLoopback
    }
}
