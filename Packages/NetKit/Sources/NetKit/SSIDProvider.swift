import CoreLocation
import CoreWLAN
import Foundation

public enum SSIDAuthorizationStatus: Sendable, Equatable {
    case notDetermined
    case authorized
    case denied
    /// No usable Location stack — unbundled process (swift test) or restricted.
    case unavailable
}

/// Reads the current Wi-Fi network name. macOS 14+ gates SSID access behind
/// Location authorization, so this owns the CLLocationManager flow too.
@MainActor
public protocol SSIDProviding: AnyObject {
    var status: SSIDAuthorizationStatus { get }
    var onStatusChange: (@MainActor (SSIDAuthorizationStatus) -> Void)? { get set }
    func requestAuthorization()
    func currentSSID() -> String?
}

@MainActor
public final class LiveSSIDProvider: NSObject, SSIDProviding {
    public var onStatusChange: (@MainActor (SSIDAuthorizationStatus) -> Void)?

    // Created lazily so constructing the provider (or NetModule) never touches
    // CoreLocation; `CLLocationManager` traps in unbundled test runners, same
    // reason NotificationService guards on the bundle identifier.
    private var manager: CLLocationManager?

    public var status: SSIDAuthorizationStatus {
        guard Bundle.main.bundleIdentifier != nil else { return .unavailable }
        return Self.map(locationManager.authorizationStatus)
    }

    public func requestAuthorization() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        locationManager.requestWhenInUseAuthorization()
    }

    public func currentSSID() -> String? {
        // Returns nil without Location authorization — the panel row simply
        // doesn't render, which is the designed denied-state behavior.
        CWWiFiClient.shared().interface()?.ssid()
    }

    private var locationManager: CLLocationManager {
        if let manager { return manager }
        let created = CLLocationManager()
        created.delegate = self
        manager = created
        return created
    }

    private static func map(_ status: CLAuthorizationStatus) -> SSIDAuthorizationStatus {
        switch status {
        case .notDetermined: .notDetermined
        case .authorizedAlways, .authorizedWhenInUse: .authorized
        case .denied: .denied
        case .restricted: .unavailable
        @unknown default: .unavailable
        }
    }
}

extension LiveSSIDProvider: CLLocationManagerDelegate {
    public nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.onStatusChange?(self.status)
        }
    }
}
