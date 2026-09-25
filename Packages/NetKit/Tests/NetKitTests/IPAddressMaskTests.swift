import Testing
@testable import NetKit

struct IPAddressMaskTests {
    @Test func ipv4KeepsOnlyTheLastOctet() {
        #expect(IPAddressMask.mask("192.168.1.50") == "•••.•••.•.50")
    }

    @Test func ipv6KeepsOnlyTheLastGroup() {
        #expect(IPAddressMask.mask("2a02:e0:1::7b") == "••••:••:•::7b")
    }

    @Test func separatorlessInputIsLeftAlone() {
        #expect(IPAddressMask.mask("localhost") == "localhost")
    }
}
