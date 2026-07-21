import Foundation
import SystemConfiguration

/// One configured VPN service, as shown to the user.
public struct VPNServiceInfo: Sendable, Equatable {
    public var serviceID: String
    public var name: String
    public var isConnected: Bool

    public init(serviceID: String, name: String, isConnected: Bool) {
        self.serviceID = serviceID
        self.name = name
        self.isConnected = isConnected
    }
}

public struct VPNStatus: Sendable, Equatable {
    public var services: [VPNServiceInfo]
    /// The default route runs through a tunnel interface (utun/ipsec/ppp) —
    /// all traffic is inside the VPN, not just split-tunnel routes.
    public var isFullTunnel: Bool

    public init(services: [VPNServiceInfo] = [], isFullTunnel: Bool = false) {
        self.services = services
        self.isFullTunnel = isFullTunnel
    }

    public var isActive: Bool { isFullTunnel || services.contains(where: \.isConnected) }
    public var connectedNames: [String] { services.filter(\.isConnected).map(\.name) }
}

public enum VPNConnectionStatus: Sendable, Equatable {
    case connected, connecting, disconnected, invalid
}

/// Raw facts about one configured VPN-ish service. The live provider only
/// gathers these; interpretation is pure and unit-tested.
public struct VPNServiceRecord: Sendable, Equatable {
    public var serviceID: String
    public var name: String
    /// `Setup:/Network/Service/<id>/Interface` Type — "VPN", "PPP" or "IPSec".
    public var interfaceType: String
    /// `State:/Network/Service/<id>/IPv4` exists — the service holds addresses.
    public var hasActiveState: Bool
    public var connectionStatus: VPNConnectionStatus

    public init(serviceID: String, name: String, interfaceType: String,
                hasActiveState: Bool, connectionStatus: VPNConnectionStatus) {
        self.serviceID = serviceID
        self.name = name
        self.interfaceType = interfaceType
        self.hasActiveState = hasActiveState
        self.connectionStatus = connectionStatus
    }
}

public enum VPNStateInterpreter {
    /// Bare utun presence is NOT a signal — this machine idles with 21 utuns
    /// (iCloud Private Relay et al). Connected = the service says so, or it
    /// holds addresses; full tunnel = the primary interface is a tunnel.
    public static func status(records: [VPNServiceRecord], primaryInterface: String?) -> VPNStatus {
        let services = records.map { record in
            VPNServiceInfo(
                serviceID: record.serviceID,
                name: record.name,
                isConnected: record.connectionStatus == .connected || record.hasActiveState
            )
        }
        let tunnelPrefixes = ["utun", "ipsec", "ppp"]
        let fullTunnel = primaryInterface.map { name in
            tunnelPrefixes.contains { name.hasPrefix($0) }
        } ?? false
        return VPNStatus(services: services, isFullTunnel: fullTunnel)
    }
}

public protocol VPNStatusProviding: Sendable {
    /// `primaryInterface` comes from SystemNetworkConfig so both reads share
    /// one snapshot of the dynamic store's view.
    func currentStatus(primaryInterface: String?) -> VPNStatus
}

public struct LiveVPNStatusProvider: VPNStatusProviding {
    public init() {}

    public func currentStatus(primaryInterface: String?) -> VPNStatus {
        VPNStateInterpreter.status(
            records: Self.gatherRecords(),
            primaryInterface: primaryInterface
        )
    }

    private static let vpnInterfaceTypes: Set<String> = ["VPN", "PPP", "IPSec"]

    private static func gatherRecords() -> [VPNServiceRecord] {
        guard let store = SCDynamicStoreCreate(nil, "Eyrie.NetKit.VPN" as CFString, nil, nil),
              let keys = SCDynamicStoreCopyKeyList(store, "Setup:/Network/Service/[^/]+/Interface" as CFString) as? [String]
        else { return [] }

        return keys.compactMap { key -> VPNServiceRecord? in
            guard let interface = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any],
                  let type = interface["Type"] as? String,
                  vpnInterfaceTypes.contains(type)
            else { return nil }

            // "Setup:/Network/Service/<id>/Interface" → <id>
            let serviceID = key
                .replacingOccurrences(of: "Setup:/Network/Service/", with: "")
                .replacingOccurrences(of: "/Interface", with: "")

            let setup = SCDynamicStoreCopyValue(store, "Setup:/Network/Service/\(serviceID)" as CFString) as? [String: Any]
            let name = setup?["UserDefinedName"] as? String
                ?? interface["UserDefinedName"] as? String
                ?? type
            let hasState = SCDynamicStoreCopyValue(store, "State:/Network/Service/\(serviceID)/IPv4" as CFString) != nil

            return VPNServiceRecord(
                serviceID: serviceID,
                name: name,
                interfaceType: type,
                hasActiveState: hasState,
                connectionStatus: connectionStatus(for: serviceID)
            )
        }
        .sorted { $0.name < $1.name }
    }

    private static func connectionStatus(for serviceID: String) -> VPNConnectionStatus {
        guard let connection = SCNetworkConnectionCreateWithServiceID(nil, serviceID as CFString, nil, nil) else {
            return .invalid
        }
        switch SCNetworkConnectionGetStatus(connection) {
        case .connected: return .connected
        case .connecting, .disconnecting: return .connecting
        case .disconnected: return .disconnected
        case .invalid: return .invalid
        @unknown default: return .invalid
        }
    }
}
