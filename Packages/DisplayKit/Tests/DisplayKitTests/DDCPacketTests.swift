import Foundation
import Testing
@testable import DisplayKit

struct DDCPacketTests {
    // Checksums seed with 0x6E ^ 0x51 = 0x3F (destination/source addresses
    // that IOAVService passes out-of-band).

    @Test func setBrightnessPacketLayoutAndChecksum() {
        let packet = DDCPacket.setVCP(0x10, value: 50)
        #expect(packet == [0x84, 0x03, 0x10, 0x00, 0x32, 0x9A])
    }

    @Test func setVCPSplitsValueIntoHighAndLowBytes() {
        let packet = DDCPacket.setVCP(0x10, value: 0x1234)
        #expect(packet[3] == 0x12)
        #expect(packet[4] == 0x34)
    }

    @Test func readRequestLayoutAndChecksum() {
        let request = DDCPacket.readRequest(0x10)
        #expect(request == [0x82, 0x01, 0x10, 0xAC])
    }

    @Test func parseValidBrightnessReply() {
        // [src][len][op 0x02][result][vcp][type][maxHi][maxLo][curHi][curLo][chk]
        let reply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x32, 0x00]
        let parsed = try! #require(DDCPacket.parseReply(reply, code: 0x10))
        #expect(parsed.current == 50)
        #expect(parsed.max == 100)
    }

    @Test func parseHandlesSixteenBitValues() {
        let reply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x01, 0x00, 0x00, 0xFF, 0x00]
        let parsed = try! #require(DDCPacket.parseReply(reply, code: 0x10))
        #expect(parsed.current == 255)
        #expect(parsed.max == 256)
    }

    @Test func parseRejectsWrongOpcode() {
        let reply: [UInt8] = [0x6E, 0x88, 0x03, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x32, 0x00]
        #expect(DDCPacket.parseReply(reply, code: 0x10) == nil)
    }

    @Test func parseRejectsMismatchedVCPCode() {
        let reply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x12, 0x00, 0x00, 0x64, 0x00, 0x32, 0x00]
        #expect(DDCPacket.parseReply(reply, code: 0x10) == nil)
    }

    @Test func parseRejectsTruncatedReply() {
        #expect(DDCPacket.parseReply([0x6E, 0x88, 0x02], code: 0x10) == nil)
        #expect(DDCPacket.parseReply([], code: 0x10) == nil)
    }
}

/// Read-only smoke test against IOKit: with no displays requested, the DDC
/// service must return nothing and touch nothing.
struct DDCServiceTests {
    @Test func refreshWithNoDisplaysReturnsEmpty() async {
        let infos = await DDCService.shared.refresh(displays: [])
        #expect(infos.isEmpty)
    }
}
