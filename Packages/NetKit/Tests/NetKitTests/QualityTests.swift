import Foundation
import Testing
@testable import NetKit

struct ICMPPacketTests {
    @Test func checksumMatchesRFC1071Vector() {
        // Classic RFC 1071 example: 00 01 f2 03 f4 f5 f6 f7 → sum 0xddf2.
        let data = Data([0x00, 0x01, 0xf2, 0x03, 0xf4, 0xf5, 0xf6, 0xf7])
        #expect(ICMPPacket.checksum(data) == ~UInt16(0xddf2))
    }

    @Test func encodedPacketChecksumsToZero() {
        // Property of a correct one's-complement checksum: re-summing the
        // packet with the checksum in place yields 0.
        let packet = ICMPPacket(identifier: 0xbeef, sequence: 42).encoded()
        #expect(ICMPPacket.checksum(packet) == 0)
        #expect(packet[0] == 8)
        #expect(packet[1] == 0)
    }

    @Test func oddLengthPayloadStillChecksumsToZero() {
        let packet = ICMPPacket(identifier: 1, sequence: 2, payload: Data([0xff])).encoded()
        #expect(ICMPPacket.checksum(packet) == 0)
    }

    @Test func parsesReplyWithSyntheticIPHeader() {
        // 20-byte IPv4 header (0x45 = version 4, IHL 5) + echo reply.
        var raw = Data(repeating: 0, count: 20)
        raw[0] = 0x45
        raw.append(contentsOf: [0, 0, 0, 0, 0xbe, 0xef, 0x00, 0x2a])
        let reply = ICMPPacket.parseReply(raw)
        #expect(reply == ICMPReply(identifier: 0xbeef, sequence: 42))
    }

    @Test func parsesBareReplyWithoutIPHeader() {
        // First byte 0x00 (type 0) has version nibble 0 — no header to skip.
        let raw = Data([0, 0, 0, 0, 0x12, 0x34, 0x00, 0x07])
        let reply = ICMPPacket.parseReply(raw)
        #expect(reply == ICMPReply(identifier: 0x1234, sequence: 7))
    }

    @Test func rejectsEchoRequestAndTruncatedData() {
        var raw = Data(repeating: 0, count: 20)
        raw[0] = 0x45
        raw.append(contentsOf: [8, 0, 0, 0, 0, 1, 0, 1])  // type 8 = request
        #expect(ICMPPacket.parseReply(raw) == nil)
        #expect(ICMPPacket.parseReply(Data([0x45, 0, 0])) == nil)
        #expect(ICMPPacket.parseReply(Data()) == nil)
    }
}

struct PingStatsTests {
    @Test func medianOfOddCount() {
        #expect(PingStats.medianLatency([0.030, nil, 0.010, 0.020]) == 0.020)
    }

    @Test func medianOfEvenCountAverages() {
        #expect(PingStats.medianLatency([0.010, 0.030]) == 0.020)
    }

    @Test func allTimeoutsHaveNoMedianAndFullLoss() {
        let latencies: [TimeInterval?] = [nil, nil, nil]
        #expect(PingStats.medianLatency(latencies) == nil)
        #expect(PingStats.lossFraction(latencies) == 1.0)
    }

    @Test func emptyWindowIsNil() {
        #expect(PingStats.medianLatency([]) == nil)
        #expect(PingStats.lossFraction([]) == nil)
    }

    @Test func lossFractionCountsOnlyTimeouts() {
        #expect(PingStats.lossFraction([0.01, nil, 0.02, 0.03]) == 0.25)
    }
}

/// Replays per-host latencies; unknown hosts time out.
final class ScriptedPinger: Pinging, @unchecked Sendable {
    private let lock = NSLock()
    private let latencies: [String: TimeInterval]
    private var pinged: [String] = []

    init(_ latencies: [String: TimeInterval]) {
        self.latencies = latencies
    }

    var pingedHosts: [String] {
        lock.withLock { pinged }
    }

    func ping(host: String, sequence: UInt16, timeout: TimeInterval) async -> PingResult {
        lock.withLock { pinged.append(host) }
        return PingResult(sequence: sequence, latency: latencies[host])
    }
}

@MainActor
struct NetModuleQualityTests {
    private func makeModule(pinger: ScriptedPinger) -> NetModule {
        let module = NetModule(
            pathMonitor: ScriptedMonitor(),
            externalIPFetcher: ScriptedFetcher(),
            configProvider: StubConfigProvider(config: SystemNetworkConfig(
                dnsServers: ["192.168.1.1"], routerAddress: "192.168.1.1",
                primaryInterface: "en0"
            )),
            vpnProvider: StubVPNProvider(),
            firewallProvider: ScriptedFirewallProvider(),
            captiveChecker: ScriptedCaptiveChecker(),
            pinger: pinger,
            defaults: temporaryDefaults()
        )
        module.showQuality = true
        return module
    }

    @Test func tickPingsGatewayAndInternet() async {
        let pinger = ScriptedPinger(["192.168.1.1": 0.004, "1.1.1.1": 0.012])
        let module = makeModule(pinger: pinger)
        module.apply(wifiSnapshot())

        await module.qualityTick()
        #expect(Set(pinger.pingedHosts) == ["192.168.1.1", "1.1.1.1"])
        #expect(module.qualityHistory.count == 1)
        #expect(module.qualityHistory.last?.gatewayLatency == 0.004)
        #expect(module.qualityHistory.last?.internetLatency == 0.012)
    }

    @Test func timeoutRecordsLoss() async {
        let pinger = ScriptedPinger(["192.168.1.1": 0.004])  // 1.1.1.1 times out
        let module = makeModule(pinger: pinger)
        module.apply(wifiSnapshot())

        await module.qualityTick()
        #expect(module.qualityHistory.last?.internetLatency == nil)
        #expect(module.qualityHistory.last?.gatewayLatency == 0.004)
    }

    @Test func offlineTickIsSkipped() async {
        let pinger = ScriptedPinger([:])
        let module = makeModule(pinger: pinger)
        module.apply(offlineSnapshot)

        await module.qualityTick()
        #expect(pinger.pingedHosts.isEmpty)
        #expect(module.qualityHistory.isEmpty)
    }

    @Test func identityChangeClearsHistory() async {
        let pinger = ScriptedPinger(["1.1.1.1": 0.010])
        let module = makeModule(pinger: pinger)
        module.apply(wifiSnapshot())
        await module.qualityTick()
        #expect(!module.qualityHistory.isEmpty)

        module.apply(ethernetSnapshot())
        #expect(module.qualityHistory.isEmpty)
    }

    @Test func disablingQualityClearsHistory() async {
        let pinger = ScriptedPinger(["1.1.1.1": 0.010])
        let module = makeModule(pinger: pinger)
        module.apply(wifiSnapshot())
        await module.qualityTick()

        module.showQuality = false
        #expect(module.qualityHistory.isEmpty)
    }
}
