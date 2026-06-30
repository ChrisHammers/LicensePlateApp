//
//  XpProgressionDebugExportButton.swift
//  LicensePlateApp
//
//  DEBUG — Share / copy JSON XP debug snapshot (ledger + server progression).
//

import SwiftUI

#if DEBUG

struct XpProgressionDebugExportButton: View {
    let userId: String
    var sessionContext: XpProgressionDebugExporter.SessionContext?

    @State private var showShareSheet = false
    @State private var exportText: String?
    @State private var exportError: String?
    @State private var didCopyToClipboard = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: export) {
                Label("Export XP debug JSON", systemImage: "square.and.arrow.up")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.Theme.primaryBlue)
            .disabled(userId.isEmpty)

            if didCopyToClipboard {
                Text("Copied to clipboard. Share sheet opened if available.")
                    .font(.caption2)
                    .foregroundStyle(Color.Theme.softBrown)
            }

            if let exportError {
                Text(exportError)
                    .font(.caption2)
                    .foregroundStyle(Color.red.opacity(0.9))
            }
        }
        .sheet(isPresented: $showShareSheet, onDismiss: { exportText = nil }) {
            if let exportText {
                ShareSheet(activityItems: [exportText])
            }
        }
    }

    private func export() {
        exportError = nil
        didCopyToClipboard = false
        do {
            let json = try XpProgressionDebugExporter.buildJSON(
                userId: userId,
                sessionContext: sessionContext
            )
            exportText = json
            UIPasteboard.general.string = json
            didCopyToClipboard = true
            showShareSheet = true
            print("—— XP debug export ——")
            print(json)
            print("—— end XP debug export ——")
        } catch {
            exportError = error.localizedDescription
        }
    }
}

#endif
