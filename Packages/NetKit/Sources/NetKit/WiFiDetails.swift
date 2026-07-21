import CoreWLAN
import EyrieCore
import Foundation

/// Signal + link details of the associated Wi-Fi network.
public struct WiFiDetails: Sendable, Equatable {
    public var rssi: Int
    public var noise: Int
    public var channelNumber: Int
    public var band: String
    public var channelWidth: String
    public var phyMode: String
    public var securityLabel: String
    /// Strictly `CWSecurity.none` — an unknown/redacted security type must
    /// never render an "Open network" warning.
    public var isOpenNetwork: Bool
    /// WEP or WPA1/TKIP: encrypted on paper, broken in practice. Same
    /// definitive-only rule as `isOpenNetwork`.
    public var isWeakSecurity: Bool

    public var snr: Int { rssi - noise }

    public init(rssi: Int, noise: Int, channelNumber: Int, band: String,
                channelWidth: String, phyMode: String, securityLabel: String,
                isOpenNetwork: Bool, isWeakSecurity: Bool = false) {
        self.rssi = rssi
        self.noise = noise
        self.channelNumber = channelNumber
        self.band = band
        self.channelWidth = channelWidth
        self.phyMode = phyMode
        self.securityLabel = securityLabel
        self.isOpenNetwork = isOpenNetwork
        self.isWeakSecurity = isWeakSecurity
    }
}

public enum WiFiSignalGrade: Sendable, Equatable {
    case excellent, good, fair, weak

    public init(rssi: Int) {
        switch rssi {
        case (-55)...: self = .excellent
        case (-67)...: self = .good
        case (-75)...: self = .fair
        default: self = .weak
        }
    }

    public var label: String {
        switch self {
        case .excellent: "Excellent"
        case .good: "Good"
        case .fair: "Fair"
        case .weak: "Weak"
        }
    }

    /// Same vocabulary as the quality row and StatsKit's memory pressure, so
    /// "this is bad" looks identical everywhere in the app.
    public var tone: StatusTone {
        switch self {
        case .excellent, .good: .normal
        case .fair: .caution
        case .weak: .critical
        }
    }
}

public extension SSIDProviding {
    /// Default keeps existing conformers (and test stubs) source-compatible.
    func currentWiFiDetails() -> WiFiDetails? { nil }
}

extension LiveSSIDProvider {
    public func currentWiFiDetails() -> WiFiDetails? {
        guard let interface = CWWiFiClient.shared().interface() else { return nil }
        let rssi = interface.rssiValue()
        // 0 means "not associated" (or fully redacted) — no row beats a lie.
        guard rssi != 0 else { return nil }
        let channel = interface.wlanChannel()
        let security = interface.security()
        return WiFiDetails(
            rssi: rssi,
            noise: interface.noiseMeasurement(),
            channelNumber: channel?.channelNumber ?? 0,
            band: Self.bandLabel(channel?.channelBand),
            channelWidth: Self.widthLabel(channel?.channelWidth),
            phyMode: Self.phyLabel(interface.activePHYMode()),
            securityLabel: Self.securityLabel(security),
            isOpenNetwork: security == CWSecurity.none,
            isWeakSecurity: Self.weakSecurityTypes.contains(security)
        )
    }

    /// Deliberately excludes `.unknown` — a redacted type is not evidence.
    private static let weakSecurityTypes: Set<CWSecurity> = [
        .WEP, .dynamicWEP, .wpaPersonal, .wpaPersonalMixed, .wpaEnterprise, .wpaEnterpriseMixed,
    ]

    private static func bandLabel(_ band: CWChannelBand?) -> String {
        switch band {
        case .band2GHz: "2.4 GHz"
        case .band5GHz: "5 GHz"
        case .band6GHz: "6 GHz"
        default: ""
        }
    }

    private static func widthLabel(_ width: CWChannelWidth?) -> String {
        switch width {
        case .width20MHz: "20 MHz"
        case .width40MHz: "40 MHz"
        case .width80MHz: "80 MHz"
        case .width160MHz: "160 MHz"
        default: ""
        }
    }

    private static func phyLabel(_ mode: CWPHYMode) -> String {
        switch mode {
        case .mode11a: "802.11a"
        case .mode11b: "802.11b"
        case .mode11g: "802.11g"
        case .mode11n: "802.11n"
        case .mode11ac: "802.11ac"
        case .mode11ax: "802.11ax"
        case .mode11be: "802.11be"
        case .modeNone: ""
        @unknown default: "Wi-Fi"
        }
    }

    private static func securityLabel(_ security: CWSecurity) -> String {
        switch security {
        case .none: "Open"
        case .WEP: "WEP"
        case .wpaPersonal, .wpaPersonalMixed: "WPA Personal"
        case .wpa2Personal: "WPA2 Personal"
        case .personal: "Personal"
        case .dynamicWEP: "Dynamic WEP"
        case .wpaEnterprise, .wpaEnterpriseMixed: "WPA Enterprise"
        case .wpa2Enterprise: "WPA2 Enterprise"
        case .enterprise: "Enterprise"
        case .wpa3Personal: "WPA3 Personal"
        case .wpa3Enterprise: "WPA3 Enterprise"
        case .wpa3Transition: "WPA3 Transition"
        case .OWE: "OWE"
        case .oweTransition: "OWE Transition"
        case .unknown: ""
        @unknown default: ""
        }
    }
}
