//
//  TripSessionRow.swift
//  LicensePlateApp
//
//  Step 12 — Row for a TripSession when no backing Trip is available for display (e.g. session-only flows).
//

import SwiftUI

/// Displays a single TripSession in the active list when TripRow cannot be used (no Trip loaded for session.id).
struct TripSessionRow: View {
    let session: TripSession

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private var dateLabel: String {
        if let started = session.startedAt {
            return dateFormatter.string(from: started)
        }
        return "—"
    }

    private var dateCaption: String {
        session.startedAt != nil ? "Started".localized : "Created".localized
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(session.name)
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)

                Spacer()

                Label("—", systemImage: "licenseplate")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                    .accessibilityLabel("Progress not available".localized)
            }

            Divider()
                .background(Color.Theme.softBrown.opacity(0.2))
                .accessibilityHidden(true)

            HStack {
                Label(dateCaption, systemImage: "calendar")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                    .accessibilityLabel(dateCaption)

                Spacer()

                Text(dateLabel)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                    .accessibilityLabel("Date: \(dateLabel)".localized)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.Theme.cardBackground)
                .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Trip: %@".localized(session.name))
        .accessibilityHint("Double tap to open trip".localized)
    }
}

#Preview {
    List {
        TripSessionRow(session: TripSession(
            name: "Preview Session",
            status: .active,
            mode: .solo,
            startedAt: Date()
        ))
    }
    .listStyle(.insetGrouped)
}
