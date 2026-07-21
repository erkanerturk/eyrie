import Foundation
@testable import NetKit

/// Replays scripted fetch results; thread-safe for strict concurrency.
final class ScriptedFetcher: ExternalIPFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [Result<String, any Error>]
    private var count = 0
    private let hangs: Bool

    init(_ results: [Result<String, any Error>] = [.success("81.2.69.142")], hangs: Bool = false) {
        queue = results
        self.hangs = hangs
    }

    var fetchCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func fetch() async throws -> String {
        let next = dequeue()
        if hangs {
            // Parks until the caller cancels; Task.sleep throws on cancellation.
            try await Task.sleep(for: .seconds(3600))
        }
        guard let next else { throw URLError(.badServerResponse) }
        return try next.get()
    }

    private func dequeue() -> Result<String, any Error>? {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return queue.isEmpty ? nil : queue.removeFirst()
    }
}

/// Counts how many fresh streams the module asks for; never yields.
final class ScriptedMonitor: NetworkPathMonitoring, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var streamCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func snapshots() -> AsyncStream<NetworkSnapshot> {
        lock.lock()
        count += 1
        lock.unlock()
        return AsyncStream { _ in }
    }
}

@MainActor
final class StubSSIDProvider: SSIDProviding {
    var status: SSIDAuthorizationStatus
    var ssidValue: String?
    var detailsValue: WiFiDetails?
    var onStatusChange: (@MainActor (SSIDAuthorizationStatus) -> Void)?
    private(set) var requestCount = 0

    init(status: SSIDAuthorizationStatus, ssid: String? = nil, details: WiFiDetails? = nil) {
        self.status = status
        ssidValue = ssid
        detailsValue = details
    }

    func requestAuthorization() { requestCount += 1 }
    func currentSSID() -> String? { ssidValue }
    func currentWiFiDetails() -> WiFiDetails? { detailsValue }
}

/// Returns a fixed config; nil simulates "dynamic store unavailable".
struct StubConfigProvider: SystemNetworkConfigProviding {
    var config: SystemNetworkConfig?

    func currentConfig() -> SystemNetworkConfig? { config }
}

/// Replays a fixed VPN status and records the primary interface asked about.
final class StubVPNProvider: VPNStatusProviding, @unchecked Sendable {
    private let lock = NSLock()
    private let status: VPNStatus
    private var interfaces: [String?] = []

    init(_ status: VPNStatus = VPNStatus()) {
        self.status = status
    }

    var askedInterfaces: [String?] {
        lock.lock()
        defer { lock.unlock() }
        return interfaces
    }

    func currentStatus(primaryInterface: String?) -> VPNStatus {
        lock.lock()
        interfaces.append(primaryInterface)
        lock.unlock()
        return status
    }
}

final class ScriptedFirewallProvider: FirewallStateProviding, @unchecked Sendable {
    private let lock = NSLock()
    private let state: FirewallState
    private var calls = 0

    init(_ state: FirewallState = .enabled) {
        self.state = state
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    func currentState() async -> FirewallState {
        lock.withLock { calls += 1 }
        return state
    }
}

final class ScriptedCaptiveChecker: CaptivePortalChecking, @unchecked Sendable {
    private let lock = NSLock()
    private let result: InternetReachability
    private var calls = 0

    init(_ result: InternetReachability = .fullInternet) {
        self.result = result
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    func check() async -> InternetReachability {
        lock.withLock { calls += 1 }
        return result
    }
}

func stubWiFiDetails(rssi: Int = -52, isOpen: Bool = false, weak: Bool = false) -> WiFiDetails {
    let label = isOpen ? "Open" : (weak ? "WEP" : "WPA3 Personal")
    return WiFiDetails(rssi: rssi, noise: -90, channelNumber: 44, band: "5 GHz",
                       channelWidth: "80 MHz", phyMode: "802.11ax",
                       securityLabel: label,
                       isOpenNetwork: isOpen, isWeakSecurity: weak)
}

/// Returns a fixed set of exposed services and counts the scans.
final class ScriptedExposedServicesProvider: ExposedServicesProviding, @unchecked Sendable {
    private let lock = NSLock()
    private let services: [ExposedService]
    private var calls = 0

    init(_ services: [ExposedService] = []) {
        self.services = services
    }

    var callCount: Int {
        lock.withLock { calls }
    }

    func currentServices() async -> [ExposedService] {
        lock.withLock { calls += 1 }
        return services
    }
}

/// Mutable fake clock injected as NetModule's `now`.
final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSinceReferenceDate: 800_000_000)

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return date
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        date = date.addingTimeInterval(interval)
        lock.unlock()
    }
}

func wifiSnapshot(interface: String = "en0", ipv4: String? = "192.168.1.42") -> NetworkSnapshot {
    NetworkSnapshot(kind: .wifi, interfaceName: interface, localIPv4: ipv4)
}

func ethernetSnapshot(interface: String = "en5", ipv4: String? = "192.168.1.50") -> NetworkSnapshot {
    NetworkSnapshot(kind: .ethernet, interfaceName: interface, localIPv4: ipv4)
}

let offlineSnapshot = NetworkSnapshot(kind: .offline)
