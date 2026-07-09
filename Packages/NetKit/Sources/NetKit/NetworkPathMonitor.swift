import Foundation
import Network

/// Push-based network path updates. Each `snapshots()` call must return a
/// fresh stream backed by a fresh monitor: a cancelled `NWPathMonitor` cannot
/// be restarted, and the panel opens/closes many times per app run.
public protocol NetworkPathMonitoring: Sendable {
    func snapshots() -> AsyncStream<NetworkSnapshot>
}

public struct LiveNetworkPathMonitor: NetworkPathMonitoring {
    public init() {}

    public func snapshots() -> AsyncStream<NetworkSnapshot> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                continuation.yield(Self.snapshot(from: path))
            }
            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: DispatchQueue(label: "com.erkanerturk.eyrie.netkit.path"))
        }
    }

    private static func snapshot(from path: NWPath) -> NetworkSnapshot {
        guard path.status == .satisfied else {
            return NetworkSnapshot(kind: .offline)
        }
        let kind: ConnectionKind = if path.usesInterfaceType(.wifi) {
            .wifi
        } else if path.usesInterfaceType(.wiredEthernet) {
            .ethernet
        } else {
            .other
        }
        // First interface is the one in use (ordered by system preference).
        guard let interface = path.availableInterfaces.first?.name else {
            return NetworkSnapshot(kind: kind)
        }
        let (ipv4, ipv6) = LocalAddress.primaryAddresses(
            in: LocalAddress.readInterfaceAddresses(),
            interface: interface
        )
        return NetworkSnapshot(kind: kind, interfaceName: interface,
                               localIPv4: ipv4, localIPv6: ipv6)
    }
}
