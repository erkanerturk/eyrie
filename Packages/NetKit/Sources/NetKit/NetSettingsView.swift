import EyrieCore
import SwiftUI

struct NetSettingsView: View {
    @Bindable var module: NetModule

    var body: some View {
        Form {
            Section("Status") {
                Toggle("Show status badges", isOn: $module.showStatusBadges)
                Text("Connection type, VPN, firewall and connectivity are checked only while the panel is open, at most once a minute.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Show security warnings", isOn: $module.showSecurityWarnings)
                Text("Flags open or weakly encrypted networks, a disabled firewall, a missing VPN, and sharing services other devices can reach. Nothing is scanned on a trusted network.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Show DNS servers", isOn: $module.showDNS)
                Toggle("Show connection quality", isOn: $module.showQuality)
                Text("Latency and loss, measured by pinging the gateway and 1.1.1.1 every two seconds while the panel is open.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Wi-Fi") {
                Toggle("Show network name", isOn: $module.showSSID)
                if module.showSSID, module.ssidAuthorization == .denied {
                    Text("Location access is required to read the network name. Enable it for Eyrie in System Settings → Privacy & Security → Location Services.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("macOS requires Location permission to read the Wi-Fi network name. Turning this on asks for it once.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Show signal details", isOn: $module.showWiFiDetails)
                Text("Signal strength, channel and link mode of the connected network.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("The external IP is only fetched while the panel is open and cached for five minutes — Eyrie never polls in the background.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .onAppear { module.refreshSSIDAuthorizationIfOptedIn() }
    }
}
