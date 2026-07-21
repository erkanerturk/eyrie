/// Where DNS queries are going, at a glance.
public enum DNSClassification: Sendable, Equatable {
    /// Every resolver is the default gateway — the router answers DNS.
    case routerDefault
    /// All resolvers belong to one well-known public provider.
    case publicResolver(String)
    case custom

    public var label: String {
        switch self {
        case .routerDefault: "Router default"
        case .publicResolver(let name): name
        case .custom: "Custom"
        }
    }
}

public enum DNSClassifier {
    private static let knownResolvers: [String: String] = [
        "1.1.1.1": "Cloudflare", "1.0.0.1": "Cloudflare",
        "2606:4700:4700::1111": "Cloudflare", "2606:4700:4700::1001": "Cloudflare",
        "8.8.8.8": "Google", "8.8.4.4": "Google",
        "2001:4860:4860::8888": "Google", "2001:4860:4860::8844": "Google",
        "9.9.9.9": "Quad9", "149.112.112.112": "Quad9",
        "2620:fe::fe": "Quad9", "2620:fe::9": "Quad9",
        "208.67.222.222": "OpenDNS", "208.67.220.220": "OpenDNS",
        "94.140.14.14": "AdGuard", "94.140.15.15": "AdGuard",
    ]

    public static func classify(servers: [String], router: String?) -> DNSClassification? {
        guard !servers.isEmpty else { return nil }
        if let router, servers.allSatisfy({ $0 == router }) {
            return .routerDefault
        }
        let providers = Set(servers.compactMap { knownResolvers[$0] })
        if providers.count == 1, servers.allSatisfy({ knownResolvers[$0] != nil }) {
            return .publicResolver(providers.first!)
        }
        return .custom
    }
}
