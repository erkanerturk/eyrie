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
    public private(set) var config: SystemNetworkConfig?
    public private(set) var vpnStatus: VPNStatus?
    public private(set) var firewallState: FirewallState?
    public private(set) var reachability: InternetReachability?
    public private(set) var wifiDetails: WiFiDetails?
    public private(set) var qualityHistory = RingBuffer<QualitySample>(capacity: 60)
    public private(set) var exposedServices: [ExposedService] = []
    /// Ordered worst-first; empty means nothing worth saying.
    public private(set) var securityFindings: [SecurityFinding] = []

    public var showSSID: Bool {
        didSet {
            defaults.set(showSSID, forKey: Self.showSSIDKey)
            handleShowSSIDChange()
        }
    }
    public var showStatusBadges: Bool {
        didSet {
            defaults.set(showStatusBadges, forKey: Self.showStatusBadgesKey)
            // Turning it on with the panel already open must not wait for the
            // next path event.
            if showStatusBadges, monitorTask != nil {
                refreshFirewallIfNeeded(force: false)
                refreshReachabilityIfNeeded(force: false)
            }
        }
    }
    public var showSecurityWarnings: Bool {
        didSet {
            defaults.set(showSecurityWarnings, forKey: Self.showSecurityWarningsKey)
            if showSecurityWarnings, monitorTask != nil {
                refreshWiFiDetails()
                refreshFirewallIfNeeded(force: false)
            }
            refreshSecurityFindings()
        }
    }
    public var showDNS: Bool {
        didSet { defaults.set(showDNS, forKey: Self.showDNSKey) }
    }
    public var showWiFiDetails: Bool {
        didSet {
            defaults.set(showWiFiDetails, forKey: Self.showWiFiDetailsKey)
            refreshWiFiDetails()
        }
    }
    public var showQuality: Bool {
        didSet {
            defaults.set(showQuality, forKey: Self.showQualityKey)
            if showQuality {
                if monitorTask != nil { startQualityLoopIfNeeded() }
            } else {
                stopQualityLoop()
                qualityHistory.removeAll()
            }
        }
    }

    @ObservationIgnored private let pathMonitor: any NetworkPathMonitoring
    @ObservationIgnored private let externalIPFetcher: any ExternalIPFetching
    @ObservationIgnored private var ssidProvider: (any SSIDProviding)?
    @ObservationIgnored private let configProvider: any SystemNetworkConfigProviding
    @ObservationIgnored private let vpnProvider: any VPNStatusProviding
    @ObservationIgnored private let firewallProvider: any FirewallStateProviding
    @ObservationIgnored private let captiveChecker: any CaptivePortalChecking
    @ObservationIgnored private let exposedServicesProvider: any ExposedServicesProviding
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    @ObservationIgnored var externalIPTask: Task<Void, Never>?
    @ObservationIgnored private var externalIPFetchedAt: Date?
    @ObservationIgnored var firewallTask: Task<Void, Never>?
    @ObservationIgnored private var firewallCheckedAt: Date?
    @ObservationIgnored var reachabilityTask: Task<Void, Never>?
    @ObservationIgnored private var reachabilityCheckedAt: Date?
    @ObservationIgnored var exposedServicesTask: Task<Void, Never>?
    @ObservationIgnored private var exposedServicesCheckedAt: Date?
    @ObservationIgnored private let pinger: any Pinging
    @ObservationIgnored private var qualityTask: Task<Void, Never>?
    @ObservationIgnored private var qualityTickIndex = 0
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let logger = Logger(subsystem: "com.erkanerturk.eyrie", category: "Net")

    private static let showSSIDKey = "net.showSSID"
    private static let showStatusBadgesKey = "net.showStatusBadges"
    private static let showDNSKey = "net.showDNS"
    private static let showWiFiDetailsKey = "net.showWiFiDetails"
    private static let showQualityKey = "net.showQuality"
    private static let showSecurityWarningsKey = "net.showSecurityWarnings"
    static let externalIPTTL: TimeInterval = 300
    /// Firewall + captive checks share this cache window across panel opens.
    static let statusTTL: TimeInterval = 60
    static let qualityInterval: TimeInterval = 2
    static let pingTimeout: TimeInterval = 1

    public init(
        pathMonitor: any NetworkPathMonitoring = LiveNetworkPathMonitor(),
        externalIPFetcher: any ExternalIPFetching = LiveExternalIPFetcher(),
        ssidProvider: (any SSIDProviding)? = nil,
        configProvider: any SystemNetworkConfigProviding = LiveSystemNetworkConfigProvider(),
        vpnProvider: any VPNStatusProviding = LiveVPNStatusProvider(),
        firewallProvider: any FirewallStateProviding = LiveFirewallStateProvider(),
        captiveChecker: any CaptivePortalChecking = LiveCaptivePortalChecker(),
        exposedServicesProvider: any ExposedServicesProviding = LiveExposedServicesProvider(),
        pinger: any Pinging = PingService(),
        now: @escaping () -> Date = Date.init
    ) {
        self.pathMonitor = pathMonitor
        self.externalIPFetcher = externalIPFetcher
        self.ssidProvider = ssidProvider
        self.configProvider = configProvider
        self.vpnProvider = vpnProvider
        self.firewallProvider = firewallProvider
        self.captiveChecker = captiveChecker
        self.exposedServicesProvider = exposedServicesProvider
        self.pinger = pinger
        self.now = now
        showSSID = defaults.object(forKey: Self.showSSIDKey) as? Bool ?? false
        showStatusBadges = defaults.object(forKey: Self.showStatusBadgesKey) as? Bool ?? true
        showDNS = defaults.object(forKey: Self.showDNSKey) as? Bool ?? true
        showWiFiDetails = defaults.object(forKey: Self.showWiFiDetailsKey) as? Bool ?? false
        showQuality = defaults.object(forKey: Self.showQualityKey) as? Bool ?? true
        showSecurityWarnings = defaults.object(forKey: Self.showSecurityWarningsKey) as? Bool ?? true
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
        startQualityLoopIfNeeded()
    }

    /// Called from the panel's onDisappear. Cancelling the monitor task tears
    /// the NWPathMonitor down via the stream's onTermination; the external IP
    /// and status caches survive so reopening within the TTL costs nothing.
    func end() {
        monitorTask?.cancel()
        monitorTask = nil
        externalIPTask?.cancel()
        externalIPTask = nil
        isFetchingExternalIP = false
        stopQualityLoop()
        // The firewall / captive / netstat checks are deliberately left to
        // finish: they are short read-only probes, and letting them land
        // populates the cache so the next open renders complete badges.
    }

    public func shutdown() {
        end()
        firewallTask?.cancel()
        firewallTask = nil
        reachabilityTask?.cancel()
        reachabilityTask = nil
        exposedServicesTask?.cancel()
        exposedServicesTask = nil
    }

    /// Synchronous state transition, injectable from tests.
    func apply(_ new: NetworkSnapshot) {
        let previous = snapshot
        snapshot = new
        let identityChanged = previous != nil && !previous!.sameNetworkIdentity(as: new)
        if identityChanged {
            // Different network — the cached external IP is someone else's,
            // and so are the latency samples.
            externalIPTask?.cancel()
            externalIPTask = nil
            isFetchingExternalIP = false
            externalIP = nil
            externalIPFetchedAt = nil
            qualityHistory.removeAll()
        }
        refreshExternalIPIfNeeded()
        refreshSSID()
        refreshSystemStatus(force: identityChanged)
    }

    // MARK: - Quality (latency + loss)

    private func startQualityLoopIfNeeded() {
        guard showQuality, qualityTask == nil else { return }
        qualityTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.qualityTick()
                guard !Task.isCancelled else { return }
                try? await Task.sleep(
                    for: .seconds(Self.qualityInterval),
                    tolerance: .seconds(Self.qualityInterval * 0.2)
                )
            }
        }
    }

    private func stopQualityLoop() {
        qualityTask?.cancel()
        qualityTask = nil
    }

    /// One gateway + internet ping pair; internal so tests drive it directly.
    func qualityTick() async {
        guard let snapshot, snapshot.kind != .offline else { return }
        let sequence = UInt16(truncatingIfNeeded: qualityTickIndex)
        let pinger = pinger
        let gatewayHost = config?.routerAddress
        async let internetResult = pinger.ping(
            host: "1.1.1.1", sequence: sequence, timeout: Self.pingTimeout
        )
        var gatewayLatency: TimeInterval?
        if let gatewayHost {
            gatewayLatency = await pinger.ping(
                host: gatewayHost, sequence: sequence, timeout: Self.pingTimeout
            ).latency
        }
        let internetLatency = await internetResult.latency
        guard !Task.isCancelled else { return }
        qualityHistory.append(QualitySample(
            id: qualityTickIndex,
            gatewayLatency: gatewayLatency,
            internetLatency: internetLatency
        ))
        qualityTickIndex += 1
    }

    // MARK: - Status (VPN / DNS / firewall / reachability)

    /// Config and VPN are cheap synchronous dynamic-store reads, done on every
    /// path event; the firewall and captive checks are async and TTL-cached
    /// *independently* of each other.
    private func refreshSystemStatus(force: Bool) {
        guard let snapshot else { return }
        guard snapshot.kind != .offline else {
            config = nil
            vpnStatus = nil
            wifiDetails = nil
            reachability = nil
            securityFindings = []
            return
        }
        config = configProvider.currentConfig()
        vpnStatus = vpnProvider.currentStatus(primaryInterface: config?.primaryInterface)
        refreshWiFiDetails()
        refreshFirewallIfNeeded(force: force)
        refreshReachabilityIfNeeded(force: force)
        refreshSecurityFindings()
    }

    /// Instant local read (measured 0.00 s). It used to share one task with
    /// the captive probe, so a slow network — or closing the panel first —
    /// threw the firewall result away and left the badge missing.
    private func refreshFirewallIfNeeded(force: Bool) {
        guard showStatusBadges || showSecurityWarnings else { return }
        guard firewallTask == nil else { return }
        if !force, let checkedAt = firewallCheckedAt,
           now().timeIntervalSince(checkedAt) < Self.statusTTL {
            return
        }
        firewallTask = Task { [weak self] in
            guard let provider = self?.firewallProvider else { return }
            let state = await provider.currentState()
            guard let self else { return }
            // Deliberately not cancelled by end(): this is a short, read-only
            // check, and letting it land fills the cache for the next open.
            firewallState = state
            firewallCheckedAt = now()
            firewallTask = nil
            refreshSecurityFindings()
        }
    }

    private func refreshReachabilityIfNeeded(force: Bool) {
        guard showStatusBadges || showSecurityWarnings else { return }
        guard reachabilityTask == nil else { return }
        if !force, let checkedAt = reachabilityCheckedAt,
           now().timeIntervalSince(checkedAt) < Self.statusTTL {
            return
        }
        reachabilityTask = Task { [weak self] in
            guard let checker = self?.captiveChecker else { return }
            let result = await checker.check()
            guard let self else { return }
            reachability = result
            reachabilityCheckedAt = now()
            reachabilityTask = nil
            refreshSecurityFindings()
        }
    }

    private func refreshWiFiDetails() {
        // Security checks need the Wi-Fi security type even when the user
        // hasn't opted into seeing signal details.
        guard snapshot?.kind == .wifi, showWiFiDetails || showSecurityWarnings else {
            wifiDetails = nil
            return
        }
        wifiDetails = resolvedSSIDProvider().currentWiFiDetails()
    }

    // MARK: - Security findings

    private func refreshSecurityFindings() {
        guard showSecurityWarnings, let snapshot, snapshot.kind != .offline else {
            securityFindings = []
            return
        }
        let trust = NetworkTrust.evaluate(wifi: wifiDetails, reachability: reachability)
        // Only scan for exposed services where they actually matter — on a
        // trusted network with a firewall up, nothing is spawned at all.
        if trust == .untrusted || firewallState == .disabled {
            refreshExposedServicesIfNeeded()
        } else {
            exposedServices = []
        }
        let findings = SecurityAdvisor.findings(
            trust: trust,
            wifi: wifiDetails,
            firewall: firewallState,
            vpn: vpnStatus,
            exposedServices: exposedServices
        )
        if securityFindings != findings { securityFindings = findings }
    }

    private func refreshExposedServicesIfNeeded() {
        guard exposedServicesTask == nil else { return }
        if let checkedAt = exposedServicesCheckedAt,
           now().timeIntervalSince(checkedAt) < Self.statusTTL {
            return
        }
        exposedServicesTask = Task { [weak self] in
            guard let provider = self?.exposedServicesProvider else { return }
            let services = await provider.currentServices()
            guard let self else { return }
            exposedServices = services
            exposedServicesCheckedAt = now()
            exposedServicesTask = nil
            refreshSecurityFindings()
        }
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
