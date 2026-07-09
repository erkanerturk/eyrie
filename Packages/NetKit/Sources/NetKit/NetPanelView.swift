import AppKit
import EyrieCore
import SwiftUI

struct NetPanelView: View {
    @Bindable var module: NetModule

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            statusRow
            CopyableRow(label: "Local IP", value: module.snapshot?.displayLocalIP)
            CopyableRow(label: "External IP", value: module.externalIP,
                        isLoading: module.isFetchingExternalIP)
            if module.showSSID, module.snapshot?.kind == .wifi, let ssid = module.ssid {
                HStack {
                    Text("Network")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(ssid)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .onAppear { module.begin() }
        .onDisappear { module.end() }
    }

    private var statusRow: some View {
        HStack(spacing: 6) {
            Image(systemName: kind?.symbolName ?? "wifi")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .contentTransition(.symbolEffect(.replace))
            Text(kind?.label ?? "Checking…")
                .font(.caption.weight(.medium))
            Spacer()
            if let kind {
                Circle()
                    .fill(kind == .offline ? Color.secondary : Color.green)
                    .frame(width: 6, height: 6)
            }
        }
    }

    private var kind: ConnectionKind? { module.snapshot?.kind }
}

/// Label + monospaced value + always-visible copy button. Copying is the
/// module's core action, so no hover-reveal tricks.
private struct CopyableRow: View {
    var label: String
    var value: String?
    var isLoading = false

    @State private var copied = false

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if isLoading, value == nil {
                ProgressView()
                    .controlSize(.mini)
            }
            Text(value ?? "—")
                .font(.caption.weight(.medium))
                .monospaced()
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            GlassIconButton(symbolName: copied ? "checkmark" : "document.on.document") {
                copy()
            }
            .disabled(value == nil)
        }
    }

    private func copy() {
        guard let value else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            copied = false
        }
    }
}
