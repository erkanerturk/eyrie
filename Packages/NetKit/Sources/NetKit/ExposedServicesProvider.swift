import EyrieCore
import Foundation

/// A sharing service of this Mac that is reachable from the network.
public struct ExposedService: Sendable, Equatable, Hashable {
    public var port: Int
    public var name: String

    public init(port: Int, name: String) {
        self.port = port
        self.name = name
    }
}

public protocol ExposedServicesProviding: Sendable {
    func currentServices() async -> [ExposedService]
}

/// Lists sharing services listening on a non-loopback address. `netstat -an`
/// needs no privileges and returns instantly (measured 0.00 s), so this only
/// ever runs on untrusted networks or when the firewall is off.
public struct LiveExposedServicesProvider: ExposedServicesProviding {
    public init() {}

    public func currentServices() async -> [ExposedService] {
        guard let output = try? await ProcessRunner.run(
            "/usr/sbin/netstat",
            arguments: ["-an", "-p", "tcp"],
            timeout: .seconds(3)
        ), output.terminationStatus == 0 else { return [] }
        return ListeningPortsParser.services(in: output.standardOutput)
    }
}

/// Pure parser over `netstat -an -p tcp`. Only well-known sharing ports are
/// reported: ephemeral high ports are app chatter, not something a user can
/// act on, and listing them would drown the real finding.
public enum ListeningPortsParser {
    static let knownServices: [Int: String] = [
        22: "Remote Login (SSH)",
        80: "Web Sharing",
        445: "File Sharing (SMB)",
        548: "File Sharing (AFP)",
        631: "Printer Sharing",
        3283: "Remote Management",
        5900: "Screen Sharing",
        // 7000 is AirPlay Receiver; 5000 is too, but it collides with every
        // dev server on the planet, so claiming "AirPlay" there would lie.
        7000: "AirPlay Receiver",
        8080: "Web Sharing",
    ]

    public static func services(in output: String) -> [ExposedService] {
        var found: Set<ExposedService> = []
        for line in output.split(separator: "\n") {
            let columns = line.split(separator: " ", omittingEmptySubsequences: true)
            // Proto Recv-Q Send-Q Local-Address Foreign-Address (state)
            guard columns.count >= 6, columns[5] == "LISTEN" else { continue }
            let local = String(columns[3])
            guard let port = port(from: local), !isLoopback(local) else { continue }
            guard let name = knownServices[port] else { continue }
            found.insert(ExposedService(port: port, name: name))
        }
        return found.sorted { $0.port < $1.port }
    }

    /// netstat writes `*.7000`, `192.168.1.42.5900` or `::1.22` — the port is
    /// always the final dot-separated component.
    private static func port(from address: String) -> Int? {
        guard let separator = address.lastIndex(of: ".") else { return nil }
        return Int(address[address.index(after: separator)...])
    }

    /// Strictly loopback. Link-local (`fe80:`) deliberately does NOT count —
    /// every device on the same segment can reach it, which is exactly the
    /// finding this provider exists to report.
    private static func isLoopback(_ address: String) -> Bool {
        address.hasPrefix("127.") || address.hasPrefix("::1.")
    }
}
