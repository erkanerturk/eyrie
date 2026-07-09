import Darwin
import Foundation

/// Local interface addresses. `NWPath` never exposes the local address, so the
/// path handler pairs its interface name with a `getifaddrs` walk done here.
public enum LocalAddress {
    /// Walks `getifaddrs` and returns every IPv4/IPv6 address record. This is
    /// the only unsafe-pointer code in NetKit.
    public static func readInterfaceAddresses() -> [InterfaceAddress] {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0, let first else { return [] }
        defer { freeifaddrs(first) }

        var result: [InterfaceAddress] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard let addr = entry.pointee.ifa_addr else { continue }
            let family = addr.pointee.sa_family
            guard family == UInt8(AF_INET) || family == UInt8(AF_INET6) else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let length = family == UInt8(AF_INET)
                ? socklen_t(MemoryLayout<sockaddr_in>.size)
                : socklen_t(MemoryLayout<sockaddr_in6>.size)
            guard getnameinfo(addr, length, &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }

            // IPv6 numeric hosts carry a "%en0" scope suffix — strip it.
            var address = host.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
            if let percent = address.firstIndex(of: "%") {
                address = String(address[..<percent])
            }

            let flags = Int32(entry.pointee.ifa_flags)
            result.append(InterfaceAddress(
                name: String(cString: entry.pointee.ifa_name),
                isIPv6: family == UInt8(AF_INET6),
                address: address,
                isUp: flags & IFF_UP != 0,
                isRunning: flags & IFF_RUNNING != 0,
                isLoopback: flags & IFF_LOOPBACK != 0
            ))
        }
        return result
    }

    /// Pure filter: the addresses to display for `interface`. IPv6 skips
    /// link-local (`fe80:`…) so a ULA/GUA wins when one exists.
    public static func primaryAddresses(
        in addresses: [InterfaceAddress],
        interface: String
    ) -> (ipv4: String?, ipv6: String?) {
        let usable = addresses.filter {
            $0.name == interface && $0.isUp && $0.isRunning && !$0.isLoopback
        }
        let ipv4 = usable.first { !$0.isIPv6 }?.address
        let ipv6 = usable.first { $0.isIPv6 && !$0.address.lowercased().hasPrefix("fe80:") }?.address
        return (ipv4, ipv6)
    }
}
