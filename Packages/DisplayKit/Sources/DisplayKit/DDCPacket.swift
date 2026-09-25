import Foundation

/// Pure DDC/CI packet construction and parsing, separated from the
/// IOAVService actor so the byte-level protocol is unit testable.
enum DDCPacket {
    /// Display's DDC I2C chip address.
    static let chipAddress: UInt32 = 0x37
    /// Host "source" sub-address used for DDC transactions.
    static let hostAddress: UInt32 = 0x51
    /// DDC checksums XOR over the destination (0x6E) and source (0x51) bytes,
    /// which IOAVService passes out-of-band.
    private static let checksumSeed: UInt8 = 0x6E ^ 0x51

    /// "Set VCP Feature" packet for the given code and value.
    static func setVCP(_ code: UInt8, value: Int) -> [UInt8] {
        var packet: [UInt8] = [0x84, 0x03, code, UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF), 0]
        packet[5] = packet[0..<5].reduce(checksumSeed) { $0 ^ $1 }
        return packet
    }

    /// "Get VCP Feature" request packet for the given code.
    static func readRequest(_ code: UInt8) -> [UInt8] {
        var request: [UInt8] = [0x82, 0x01, code, 0]
        request[3] = request[0..<3].reduce(checksumSeed) { $0 ^ $1 }
        return request
    }

    /// Replies checksum against the host's virtual address 0x50.
    private static let replyChecksumSeed: UInt8 = 0x50

    /// Parses a "Get VCP Feature" reply.
    /// Layout: [src][len][0x02][result][vcp][type][maxHi][maxLo][curHi][curLo][chk]
    /// A non-zero result byte means "unsupported VCP code", and a bad checksum
    /// means a corrupted transfer; neither carries a usable value.
    static func parseReply(_ reply: [UInt8], code: UInt8) -> (current: Int, max: Int)? {
        guard reply.count >= 11, reply[2] == 0x02, reply[3] == 0x00, reply[4] == code,
              reply[0..<10].reduce(replyChecksumSeed, ^) == reply[10]
        else { return nil }
        return (Int(reply[8]) << 8 | Int(reply[9]), Int(reply[6]) << 8 | Int(reply[7]))
    }

    /// Current value as 0...100 percent of `max`, clamped so a display that
    /// reports current > max can't push the slider out of range.
    static func percent(current: Int, max: Int) -> Int {
        guard max > 0 else { return 0 }
        return Swift.min(Swift.max(current, 0), max) * 100 / max
    }
}
