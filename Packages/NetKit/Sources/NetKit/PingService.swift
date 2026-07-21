import Darwin
import Foundation

public struct PingResult: Sendable, Equatable {
    public var sequence: UInt16
    /// nil means no reply within the timeout — counts as loss.
    public var latency: TimeInterval?

    public init(sequence: UInt16, latency: TimeInterval? = nil) {
        self.sequence = sequence
        self.latency = latency
    }
}

public protocol Pinging: Sendable {
    func ping(host: String, sequence: UInt16, timeout: TimeInterval) async -> PingResult
}

/// One ICMP echo round trip over an unprivileged SOCK_DGRAM socket (the
/// SimplePing mechanism — no root, no entitlement). The bounded poll+recv
/// blocks this actor's thread for up to `timeout`, the same trade DDCService
/// makes for its serial I2C; pings therefore serialize, which is fine at a
/// 2 s tick with a 1 s cap.
public actor PingService: Pinging {
    public init() {}

    public func ping(host: String, sequence: UInt16, timeout: TimeInterval) async -> PingResult {
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else {
            return PingResult(sequence: sequence)
        }
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard fd >= 0 else { return PingResult(sequence: sequence) }
        defer { close(fd) }

        let packet = ICMPPacket(
            identifier: UInt16.random(in: 0...(.max)),
            sequence: sequence
        ).encoded()
        let start = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)
        let sent = packet.withUnsafeBytes { buffer in
            withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    sendto(fd, buffer.baseAddress, buffer.count, 0,
                           sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent == packet.count else { return PingResult(sequence: sequence) }

        // The socket only receives our own ICMP traffic, but late replies from
        // a previous sequence can still arrive — keep reading until the
        // sequence matches or the deadline passes.
        while true {
            let elapsed = TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) - start) / 1e9
            let remainingMs = Int32(((timeout - elapsed) * 1000).rounded(.down))
            guard remainingMs > 0 else { return PingResult(sequence: sequence) }

            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            guard poll(&descriptor, 1, remainingMs) > 0 else {
                return PingResult(sequence: sequence)
            }
            var buffer = [UInt8](repeating: 0, count: 1024)
            let received = recv(fd, &buffer, buffer.count, 0)
            guard received > 0 else { return PingResult(sequence: sequence) }

            if let reply = ICMPPacket.parseReply(Data(buffer[..<received])),
               reply.sequence == sequence {
                let latency = TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) - start) / 1e9
                return PingResult(sequence: sequence, latency: latency)
            }
        }
    }
}
