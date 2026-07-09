import EyrieCore
import SwiftUI

struct NetSettingsView: View {
    @Bindable var module: NetModule

    var body: some View {
        Form {
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
            }
            Text("The external IP is only fetched while the panel is open and cached for five minutes — Eyrie never polls in the background.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .onAppear { module.refreshSSIDAuthorizationIfOptedIn() }
    }
}
