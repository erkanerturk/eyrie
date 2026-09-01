import CoreWLAN
import Testing
@testable import NetKit

struct PHYLabelTests {
    /// The label table mirrors the kCWPHYMode* constants in CoreWLANTypes.h;
    /// a raw-value mapping is exactly what drifts silently, so pin it.
    @Test func phyLabelCoversEveryPHYMode() {
        let expected = ["", "802.11a", "802.11b", "802.11g", "802.11n", "802.11ac", "802.11ax", "802.11be"]
        for (raw, label) in expected.enumerated() {
            #expect(LiveSSIDProvider.phyLabel(CWPHYMode(rawValue: raw)!) == label)
        }
    }

    @Test func phyLabelFallsBackForUnknownFutureModes() {
        #expect(LiveSSIDProvider.phyLabel(CWPHYMode(rawValue: 99)!) == "Wi-Fi")
    }
}
