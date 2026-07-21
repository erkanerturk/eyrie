import Foundation

/// ICMP echo framing, pure and socket-free (PingService owns the I/O — same
/// split as DisplayKit's DDCPacket/DDCService).
public struct ICMPPacket: Sendable, Equatable {
    public var identifier: UInt16
    public var sequence: UInt16
    public var payload: Data

    public init(identifier: UInt16, sequence: UInt16, payload: Data = Data("eyrie".utf8)) {
        self.identifier = identifier
        self.sequence = sequence
        self.payload = payload
    }

    /// Echo request: type 8, code 0, RFC 1071 checksum over the full message.
    public func encoded() -> Data {
        var data = Data(capacity: 8 + payload.count)
        data.append(contentsOf: [8, 0, 0, 0])
        data.append(UInt8(identifier >> 8))
        data.append(UInt8(identifier & 0xff))
        data.append(UInt8(sequence >> 8))
        data.append(UInt8(sequence & 0xff))
        data.append(payload)
        let sum = Self.checksum(data)
        data[2] = UInt8(sum >> 8)
        data[3] = UInt8(sum & 0xff)
        return data
    }

    /// One's-complement sum of big-endian 16-bit words, odd byte zero-padded.
    static func checksum(_ data: Data) -> UInt16 {
        let bytes = [UInt8](data)
        var sum: UInt32 = 0
        var index = 0
        while index + 1 < bytes.count {
            sum &+= UInt32(bytes[index]) << 8 | UInt32(bytes[index + 1])
            index += 2
        }
        if index < bytes.count {
            sum &+= UInt32(bytes[index]) << 8
        }
        while sum > 0xffff {
            sum = (sum & 0xffff) + (sum >> 16)
        }
        return ~UInt16(sum)
    }

    /// Parses an echo reply. macOS DGRAM ICMP sockets deliver the reply with
    /// the IPv4 header still attached — skip IHL×4 bytes when present. The
    /// kernel also rewrites the identifier on these sockets, so callers match
    /// replies by sequence, never by identifier.
    public static func parseReply(_ raw: Data) -> ICMPReply? {
        var bytes = [UInt8](raw)
        if let first = bytes.first, first >> 4 == 4 {
            let headerLength = Int(first & 0x0f) * 4
            guard headerLength >= 20, bytes.count > headerLength else { return nil }
            bytes.removeFirst(headerLength)
        }
        guard bytes.count >= 8 else { return nil }
        // Echo reply is type 0, code 0.
        guard bytes[0] == 0, bytes[1] == 0 else { return nil }
        return ICMPReply(
            identifier: UInt16(bytes[4]) << 8 | UInt16(bytes[5]),
            sequence: UInt16(bytes[6]) << 8 | UInt16(bytes[7])
        )
    }
}

public struct ICMPReply: Sendable, Equatable {
    public var identifier: UInt16
    public var sequence: UInt16

    public init(identifier: UInt16, sequence: UInt16) {
        self.identifier = identifier
        self.sequence = sequence
    }
}
