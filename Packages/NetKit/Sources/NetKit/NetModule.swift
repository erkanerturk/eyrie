import EyrieCore
import SwiftUI
import os

/// Network identity card: connection type, local IP, external IP, optional
/// SSID. Monitoring only runs while the panel is on screen; the external IP
/// is fetched lazily and cached, so the module costs nothing when idle.
@MainActor
@Observable
public final class NetModule: EyrieModule {
    public let id = "net"
    public let name = "Network"
    public let symbolName = "network"
    /// Passive observer — must never flip the menu bar icon to active.
    public var isActive: Bool { false }

    /// nil until the first path update arrives — the panel shows "Checking…",
    /// never a false "Offline" flash.
    public private(set) var snapshot: NetworkSnapshot?
    public private(set) var externalIP: String?
    public private(set) var isFetchingExternalIP = false
    public private(set) var ssid: String?
    /// Last observed Location authorization; nil until the user opts in.
    public private(set) var ssidAuthorization: SSIDAuthorizationStatus?

    public var showSSID: Bool {
        didSet {
            defaults.set(showSSID, forKey: Self.showSSIDKey)
            handleShowSSIDChange()
        }
    }

    @ObservationIgnored private let pathMonitor: any NetworkPathMonitoring
    @ObservationIgnored private let externalIPFetcher: any ExternalIPFetching
    @ObservationIgnored private var ssidProvider: (any SSIDProviding)?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    @ObservationIgnored var externalIPTask: Task<Void, Never>?
    @ObservationIgnored private var externalIPFetchedAt: Date?
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let logger = Logger(subsystem: "com.erkanerturk.eyrie", category: "Net")

    private static let showSSIDKey = "net.showSSID"
    static let externalIPTTL: TimeInterval = 300

    public init(
        pathMonitor: any NetworkPathMonitoring = LiveNetworkPathMonitor(),
        externalIPFetcher: any ExternalIPFetching = LiveExternalIPFetcher(),
        ssidProvider: (any SSIDProviding)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.pathMonitor = pathMonitor
        self.externalIPFetcher = externalIPFetcher
        self.ssidProvider = ssidProvider
        self.now = now
        showSSID = defaults.object(forKey: Self.showSSIDKey) as? Bool ?? false
        if let ssidProvider { hook(ssidProvider) }
    }

    /// Idempotent; called from the panel's onAppear. All fetching is driven by
    /// the snapshots the monitor pushes, so this only starts the consumer.
    func begin() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            guard let stream = self?.pathMonitor.snapshots() else { return }
            for await snapshot in stream {
                guard !Task.isCancelled else { return }
                self?.apply(snapshot)
            }
        }
    }

    /// Called from the panel's onDisappear. Cancelling the monitor task tears
    /// the NWPathMonitor down via the stream's onTermination; the external IP
    /// cache survives so reopening within the TTL costs zero traffic.
    func end() {
        monitorTask?.cancel()
        monitorTask = nil
        externalIPTask?.cancel()
        externalIPTask = nil
        isFetchingExternalIP = false
    }

    public func shutdown() {
        end()
    }

    /// Synchronous state transition, injectable from tests.
    func apply(_ new: NetworkSnapshot) {
        let previous = snapshot
        snapshot = new
        if let previous, !previous.sameNetworkIdentity(as: new) {
            // Different network — the cached external IP is someone else's.
            externalIPTask?.cancel()
            externalIPTask = nil
            isFetchingExternalIP = false
            externalIP = nil
            externalIPFetchedAt = nil
        }
        refreshExternalIPIfNeeded()
        refreshSSID()
    }

    private func refreshExternalIPIfNeeded() {
        guard let snapshot, snapshot.kind != .offline else { return }
        guard externalIPTask == nil else { return }
        if externalIP != nil, let fetchedAt = externalIPFetchedAt,
           now().timeIntervalSince(fetchedAt) < Self.externalIPTTL {
            return
        }
        isFetchingExternalIP = true
        externalIPTask = Task { [weak self] in
            guard let fetcher = self?.externalIPFetcher else { return }
            do {
                let ip = try await fetcher.fetch()
                guard let self, !Task.isCancelled else { return }
                externalIP = ip
                // Stamped only on success: a failed fetch must retry on the
                // next panel open instead of poisoning the TTL window.
                externalIPFetchedAt = now()
                isFetchingExternalIP = false
                externalIPTask = nil
            } catch {
                guard let self, !Task.isCancelled else { return }
                logger.error("External IP fetch failed: \(error)")
                isFetchingExternalIP = false
                externalIPTask = nil
            }
        }
    }

    // MARK: - SSID

    private func handleShowSSIDChange() {
        guard showSSID else {
            ssid = nil
            return
        }
        let provider = resolvedSSIDProvider()
        ssidAuthorization = provider.status
        if provider.status == .notDetermined {
            provider.requestAuthorization()
        }
        refreshSSID()
    }

    private func refreshSSID() {
        guard showSSID, snapshot?.kind == .wifi else {
            ssid = nil
            return
        }
        let provider = resolvedSSIDProvider()
        ssidAuthorization = provider.status
        ssid = provider.status == .authorized ? provider.currentSSID() : nil
    }

    /// Refreshes the authorization caption state; called when Settings opens.
    func refreshSSIDAuthorizationIfOptedIn() {
        guard showSSID else { return }
        ssidAuthorization = resolvedSSIDProvider().status
    }

    /// The live provider is created on first use, never in init: constructing
    /// `NetModule()` in the registry must not touch CoreLocation/CoreWLAN.
    private func resolvedSSIDProvider() -> any SSIDProviding {
        if let ssidProvider { return ssidProvider }
        let provider = LiveSSIDProvider()
        ssidProvider = provider
        hook(provider)
        return provider
    }

    private func hook(_ provider: any SSIDProviding) {
        provider.onStatusChange = { [weak self] status in
            self?.ssidAuthorization = status
            self?.refreshSSID()
        }
    }

    public var panelContent: AnyView { AnyView(NetPanelView(module: self)) }
    public var settingsContent: AnyView { AnyView(NetSettingsView(module: self)) }
}
