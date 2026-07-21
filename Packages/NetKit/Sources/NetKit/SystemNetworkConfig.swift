import Foundation
import SystemConfiguration

/// Global network state as configd sees it: active DNS resolvers plus the
/// primary (default-route) service. All values come from SCDynamicStore.
public struct SystemNetworkConfig: Sendable, Equatable {
    public var dnsServers: [String]
    public var searchDomains: [String]
    /// `State:/Network/Global/IPv4` Router — the default gateway.
    public var routerAddress: String?
    /// Interface carrying the default route, e.g. "en0" — or "utun6" when a
    /// full-tunnel VPN owns it.
    public var primaryInterface: String?
    public var primaryServiceID: String?

    public init(
        dnsServers: [String] = [],
        searchDomains: [String] = [],
        routerAddress: String? = nil,
        primaryInterface: String? = nil,
        primaryServiceID: String? = nil
    ) {
        self.dnsServers = dnsServers
        self.searchDomains = searchDomains
        self.routerAddress = routerAddress
        self.primaryInterface = primaryInterface
        self.primaryServiceID = primaryServiceID
    }
}

public protocol SystemNetworkConfigProviding: Sendable {
    /// Synchronous and cheap — two SCDynamicStore key reads.
    func currentConfig() -> SystemNetworkConfig?
}

public struct LiveSystemNetworkConfigProvider: SystemNetworkConfigProviding {
    public init() {}

    public func currentConfig() -> SystemNetworkConfig? {
        guard let store = SCDynamicStoreCreate(nil, "Eyrie.NetKit" as CFString, nil, nil) else {
            return nil
        }
        let ipv4 = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
        let dns = SCDynamicStoreCopyValue(store, "State:/Network/Global/DNS" as CFString) as? [String: Any]
        guard ipv4 != nil || dns != nil else { return nil }
        return SystemNetworkConfig(
            dnsServers: dns?["ServerAddresses"] as? [String] ?? [],
            searchDomains: dns?["SearchDomains"] as? [String] ?? [],
            routerAddress: ipv4?["Router"] as? String,
            primaryInterface: ipv4?["PrimaryInterface"] as? String,
            primaryServiceID: ipv4?["PrimaryService"] as? String
        )
    }
}
