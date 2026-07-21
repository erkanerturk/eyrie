import Testing
@testable import TrafficKit

struct NettopParserTests {
    @Test func headerValidation() {
        #expect(NettopParser.isValidHeader(",bytes_in,bytes_out,"))
        #expect(!NettopParser.isValidHeader(",bytes_in,bytes_out,packets_in,"))
        #expect(!NettopParser.isValidHeader("time,,bytes_in,bytes_out,"))
        #expect(!NettopParser.isValidHeader(""))
    }

    @Test func parsesGoldenFrameFromRealOutput() {
        // Verbatim rows captured from `nettop -P -x -L 1 -J bytes_in,bytes_out`
        // on this machine — dots, spaces and truncation included.
        let frame = NettopParser.parseFrame([
            "launchd.1,0,0,",
            "mDNSResponder.539,159452855,77858462,",
            "Notion Helper.30809,515791,379045,",
            "Brave Browser H.66774,28704,33400,",
            "com.apple.WebKi.11024,4523,8813,",
        ])
        #expect(frame.count == 5)
        #expect(frame[0] == ProcessTraffic(pid: 1, name: "launchd", bytesIn: 0, bytesOut: 0))
        #expect(frame[3] == ProcessTraffic(pid: 66774, name: "Brave Browser H", bytesIn: 28704, bytesOut: 33400))
        #expect(frame[4].name == "com.apple.WebKi")
        #expect(frame[4].pid == 11024)
    }

    @Test func nameContainingCommaParsesFromTheRight() {
        let row = NettopParser.parseRow("weird, name.123,10,20,")
        #expect(row == ProcessTraffic(pid: 123, name: "weird, name", bytesIn: 10, bytesOut: 20))
    }

    @Test func junkRowsAreSkippedNotFatal() {
        let frame = NettopParser.parseFrame([
            "no-counters-here",
            "name-without-pid,10,20,",
            "orphan.abc,10,20,",
            ".999,10,20,",
            "",
            "good.42,1,2,",
        ])
        #expect(frame == [ProcessTraffic(pid: 42, name: "good", bytesIn: 1, bytesOut: 2)])
    }

    @Test func negativeAndOverflowCountersAreRejected() {
        #expect(NettopParser.parseRow("app.1,-5,0,") == nil)
        #expect(NettopParser.parseRow("app.1,0,99999999999999999999999999,") == nil)
    }
}
