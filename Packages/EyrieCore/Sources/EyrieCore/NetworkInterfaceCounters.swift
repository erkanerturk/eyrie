import Darwin
import Foundation

/// One interface's lifetime traffic counters (since boot).
public struct InterfaceCounters: Sendable, Equatable {
    public var name: String
    public var bytesIn: UInt64
    public var bytesOut: UInt64
    public var isUp: Bool
    public var isRunning: Bool
    public var isLoopback: Bool

    public init(name: String, bytesIn: UInt64, bytesOut: UInt64,
                isUp: Bool, isRunning: Bool, isLoopback: Bool) {
        self.name = name
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
        self.isUp = isUp
        self.isRunning = isRunning
        self.isLoopback = isLoopback
    }
}

public enum NetworkInterfaceCountersError: Error {
    case sysctl(String, Int32)
}

/// Per-interface 64-bit byte counters via sysctl NET_RT_IFLIST2 — if_msghdr2
/// carries if_data64, while getifaddrs' if_data wraps at 4 GiB. Names come
/// from the sockaddr_dl trailing each RTM_IFINFO2 record.
public enum NetworkInterfaceCounters {
    public static func read() throws -> [InterfaceCounters] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, u_int(mib.count), nil, &length, nil, 0) == 0 else {
            throw NetworkInterfaceCountersError.sysctl("NET_RT_IFLIST2 size", errno)
        }
        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: length,
            alignment: MemoryLayout<if_msghdr2>.alignment
        )
        defer { buffer.deallocate() }
        guard sysctl(&mib, u_int(mib.count), buffer, &length, nil, 0) == 0 else {
            throw NetworkInterfaceCountersError.sysctl("NET_RT_IFLIST2", errno)
        }

        var interfaces: [InterfaceCounters] = []
        var offset = 0
        // Records are variable-length and not guaranteed aligned — walk with
        // loadUnaligned, advancing by ifm_msglen.
        while offset + MemoryLayout<if_msghdr>.size <= length {
            let header = UnsafeRawPointer(buffer).loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
            guard header.ifm_msglen > 0 else { break }
            if Int32(header.ifm_type) == RTM_IFINFO2,
               offset + MemoryLayout<if_msghdr2>.size <= length {
                let message = UnsafeRawPointer(buffer).loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                let flags = message.ifm_flags
                let name = linkName(
                    in: UnsafeRawPointer(buffer),
                    recordOffset: offset,
                    recordLength: Int(message.ifm_msglen),
                    totalLength: length
                ) ?? "if\(message.ifm_index)"
                interfaces.append(InterfaceCounters(
                    name: name,
                    bytesIn: message.ifm_data.ifi_ibytes,
                    bytesOut: message.ifm_data.ifi_obytes,
                    isUp: flags & IFF_UP != 0,
                    isRunning: flags & IFF_RUNNING != 0,
                    isLoopback: flags & IFF_LOOPBACK != 0
                ))
            }
            offset += Int(header.ifm_msglen)
        }
        return interfaces
    }

    /// Sum over interfaces that carry real traffic (up, running, non-loopback)
    /// — the aggregate StatsKit graphs.
    public static func totals(of interfaces: [InterfaceCounters]) -> (received: UInt64, sent: UInt64) {
        var received: UInt64 = 0
        var sent: UInt64 = 0
        for interface in interfaces where interface.isUp && interface.isRunning && !interface.isLoopback {
            received &+= interface.bytesIn
            sent &+= interface.bytesOut
        }
        return (received, sent)
    }

    /// Reads the sockaddr_dl following an RTM_IFINFO2 header: fixed prefix is
    /// sdl_len(1) sdl_family(1) sdl_index(2) sdl_type(1) sdl_nlen(1)
    /// sdl_alen(1) sdl_slen(1), then sdl_data holds the name for sdl_nlen bytes.
    private static func linkName(
        in buffer: UnsafeRawPointer,
        recordOffset: Int,
        recordLength: Int,
        totalLength: Int
    ) -> String? {
        let sdlOffset = recordOffset + MemoryLayout<if_msghdr2>.size
        let prefixEnd = sdlOffset + 8
        guard prefixEnd <= totalLength, prefixEnd <= recordOffset + recordLength else { return nil }
        let family = buffer.loadUnaligned(fromByteOffset: sdlOffset + 1, as: UInt8.self)
        guard Int32(family) == AF_LINK else { return nil }
        let nameLength = Int(buffer.loadUnaligned(fromByteOffset: sdlOffset + 5, as: UInt8.self))
        guard nameLength > 0, prefixEnd + nameLength <= totalLength else { return nil }
        let bytes = (0..<nameLength).map {
            buffer.loadUnaligned(fromByteOffset: prefixEnd + $0, as: UInt8.self)
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
