import Testing
@testable import NetKit

private func addr(
    _ name: String, _ address: String, v6: Bool = false,
    up: Bool = true, running: Bool = true, loopback: Bool = false
) -> InterfaceAddress {
    InterfaceAddress(name: name, isIPv6: v6, address: address,
                     isUp: up, isRunning: running, isLoopback: loopback)
}

struct LocalAddressTests {
    @Test func picksIPv4ForMatchingInterface() {
        let fixtures = [
            addr("lo0", "127.0.0.1", loopback: true),
            addr("utun4", "10.8.0.2"),
            addr("en0", "192.168.1.42"),
            addr("en0", "fd12:3456::1", v6: true),
        ]
        let (ipv4, ipv6) = LocalAddress.primaryAddresses(in: fixtures, interface: "en0")
        #expect(ipv4 == "192.168.1.42")
        #expect(ipv6 == "fd12:3456::1")
    }

    @Test func skipsDownInterfaces() {
        let fixtures = [
            addr("en0", "192.168.1.42", up: false),
            addr("en0", "169.254.0.5", running: false),
        ]
        let (ipv4, ipv6) = LocalAddress.primaryAddresses(in: fixtures, interface: "en0")
        #expect(ipv4 == nil)
        #expect(ipv6 == nil)
    }

    @Test func ipv6FallbackSkipsLinkLocal() {
        let fixtures = [
            addr("en0", "fe80::1c2d:3e4f", v6: true),
            addr("en0", "2a02:8109:9c40::7", v6: true),
        ]
        let (ipv4, ipv6) = LocalAddress.primaryAddresses(in: fixtures, interface: "en0")
        #expect(ipv4 == nil)
        #expect(ipv6 == "2a02:8109:9c40::7")
    }

    @Test func unknownInterfaceYieldsNils() {
        let fixtures = [addr("en0", "192.168.1.42")]
        let (ipv4, ipv6) = LocalAddress.primaryAddresses(in: fixtures, interface: "en5")
        #expect(ipv4 == nil)
        #expect(ipv6 == nil)
    }

    @Test func loopbackNeverWins() {
        let fixtures = [addr("lo0", "127.0.0.1", loopback: true)]
        let (ipv4, _) = LocalAddress.primaryAddresses(in: fixtures, interface: "lo0")
        #expect(ipv4 == nil)
    }
}
