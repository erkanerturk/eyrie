import SwiftUI

struct AboutSettingsView: View {
    private static let repoURL = URL(string: "https://github.com/erkanerturk/eyrie")!

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 76, height: 76)

            Text("Eyrie")
                .font(.title2.weight(.semibold))
            Text(versionString)
                .font(.callout)
                .foregroundStyle(.secondary)

            Text("Modular menu bar utilities for macOS")
                .font(.callout)
                .padding(.top, 2)

            Link(destination: Self.repoURL) {
                Label("github.com/erkanerturk/eyrie", systemImage: "link")
            }
            .padding(.top, 4)

            Spacer()

            Text("MIT License © 2026 Erkan ERTURK")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
