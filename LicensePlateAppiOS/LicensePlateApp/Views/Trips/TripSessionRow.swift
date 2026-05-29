//
//  TripSessionRow.swift
//  LicensePlateApp
//
//  Step 12 — Row for a TripSession in the active list (session-only, canonical model).
//

import SwiftUI

/// Displays a single TripSession in the active list. Shows name, date, and primary-game progress from rollup.
struct TripSessionRow: View {
    let session: TripSession
    let rollup: TripRollup
    let pendingOutgoingInviteCount: Int

    init(session: TripSession, rollup: TripRollup, pendingOutgoingInviteCount: Int = 0) {
        self.session = session
        self.rollup = rollup
        self.pendingOutgoingInviteCount = pendingOutgoingInviteCount
    }

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
        return dateFormatter.string(from: session.createdAt)
    }

    private var dateCaption: String {
        session.startedAt != nil ? "Started".localized : "Created".localized
    }

    private var plateLabel: String {
        let denom = rollup.primaryGameCompletionGoal.map { "\($0)" } ?? "—"
        return "\(rollup.primaryGameDiscoveryCount)/\(denom)"
    }

    private var accessibilityValue: String {
        if let goal = rollup.primaryGameCompletionGoal {
            return "%d of %d".localized(rollup.primaryGameDiscoveryCount, goal)
        }
        return "\(rollup.primaryGameDiscoveryCount)"
    }

    private var tripMetaLine: String {
        "%@ · %@".localized(session.mode.localizedDisplayName, rollup.gameCount == 1 ? "1 game".localized : "%d games".localized(rollup.gameCount))
        
    }

    private var pendingOutgoingInviteBadgeLabel: String {
        pendingOutgoingInviteCount == 1
            ? "1 invite pending".localized
            : "%d invites pending".localized(pendingOutgoingInviteCount)
    }

    private var combinedAccessibilityLabel: String {
        let plateFound = rollup.primaryGameDiscoveryCount == 1
            ? "1 license plate found".localized
            : "%d license plates found".localized(rollup.primaryGameDiscoveryCount)
        let gamesLine = rollup.gameCount == 1 ? "1 game".localized : "%d games".localized(rollup.gameCount)
        var lines = [
            "Trip: %@".localized(session.name),
            "Trip participation: %@".localized(session.mode.localizedDisplayName),
            gamesLine,
            plateFound,
            accessibilityValue
        ]
        if pendingOutgoingInviteCount > 0 {
            lines.append(pendingOutgoingInviteBadgeLabel)
        }
        return lines.joined(separator: ". ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(session.name)
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.Theme.primaryBlue)

                    if pendingOutgoingInviteCount > 0 {
                        Text(pendingOutgoingInviteBadgeLabel)
                            .font(.system(.caption2, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.Theme.primaryBlue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.Theme.accentYellow.opacity(0.25))
                            )
                            .accessibilityLabel(pendingOutgoingInviteBadgeLabel)
                    }
                }

                Spacer()

                Label(plateLabel, systemImage: "licenseplate")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.medium)
                    .foregroundStyle(Color.Theme.accentYellow)
                    .accessibilityLabel(rollup.primaryGameDiscoveryCount == 1 ? "1 license plate found".localized : "%d license plates found".localized(rollup.primaryGameDiscoveryCount))
                    .accessibilityValue(accessibilityValue)
            }

            Text(tripMetaLine)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
                .accessibilityHidden(true)

            if rollup.gameCount > 1 {
                Text("License plate progress (primary game)".localized)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown.opacity(0.9))
                    .accessibilityHidden(true)
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
        .accessibilityLabel(combinedAccessibilityLabel)
        .accessibilityHint("Double tap to open trip".localized)
    }
}

#Preview("Solo trip") {
    List {
        TripSessionRow(
            session: PreviewTripFixtures.soloTrip(),
            rollup: TripRollup(
                gameCount: 1,
                participantCount: 1,
                totalDiscoveryCount: 5,
                primaryGameDiscoveryCount: 5,
                primaryGameCompletionGoal: 50
            )
        )
    }
    .listStyle(.insetGrouped)
}

#Preview("Completed trip") {
    List {
        TripSessionRow(
            session: PreviewTripFixtures.completedTrip(),
            rollup: TripRollup(
                gameCount: 1,
                participantCount: 1,
                totalDiscoveryCount: 0,
                primaryGameDiscoveryCount: 0,
                primaryGameCompletionGoal: 50
            )
        )
    }
    .listStyle(.insetGrouped)
}

#Preview("Multiplayer multi-game") {
    List {
        TripSessionRow(
            session: PreviewTripFixtures.multiGameTrip(),
            rollup: TripRollup(
                gameCount: 3,
                participantCount: 1,
                totalDiscoveryCount: 10,
                primaryGameDiscoveryCount: 6,
                primaryGameCompletionGoal: 50
            )
        )
    }
    .listStyle(.insetGrouped)
}
