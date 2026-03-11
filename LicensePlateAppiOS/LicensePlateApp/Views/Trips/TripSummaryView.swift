//
//  TripSummaryView.swift
//  LicensePlateApp
//
//  Step 07 — Rich trip summary: progress, participant contributions, per-game summary, first discoveries.
//

import SwiftUI

struct TripSummaryView: View {
    let summary: TripSummary
    var onDismiss: (() -> Void)?

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                statsSection
                if !summary.participantContributions.isEmpty {
                    participantsSection
                }
                if !summary.games.isEmpty {
                    gamesSection
                }
                if let projection = summary.discoveryProjection, !projection.targetSummaries.isEmpty {
                    firstDiscoveriesSection(projection: projection)
                }
                if summary.locationMetadata != nil && !summary.locationMetadata!.isEmpty {
                    mapRecapPlaceholder
                }
            }
            .padding()
        }
        .background(Color.Theme.background)
        .navigationTitle(summary.tripName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if onDismiss != nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close".localized) {
                        FeedbackService.shared.buttonTap()
                        onDismiss?()
                    }
                    .foregroundStyle(Color.Theme.primaryBlue)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Trip summary".localized)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(summary.tripName)
                .font(.system(.title2, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(Color.Theme.primaryBlue)
            if let ended = summary.endedAt {
                Text("Ended".localized + " " + dateFormatter.string(from: ended))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                    .accessibilityLabel("Ended".localized + " " + dateFormatter.string(from: ended))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.Theme.cardBackground)
        )
    }

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overview".localized)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Color.Theme.primaryBlue)
            HStack(spacing: 24) {
                statItem(value: "\(summary.participantCount)", label: "Participants".localized)
                statItem(value: "\(summary.gameCount)", label: "Games".localized)
                statItem(value: "\(summary.totalDiscoveryCount)", label: "Discoveries".localized)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.Theme.cardBackground)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Overview".localized + ", \(summary.participantCount) participants, \(summary.gameCount) games, \(summary.totalDiscoveryCount) discoveries")
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(.title3, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(Color.Theme.primaryBlue)
            Text(label)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
        }
    }

    private var participantsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Participant contributions".localized)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Color.Theme.primaryBlue)
            ForEach(summary.participantContributions, id: \.participantId) { contrib in
                HStack {
                    Text(contrib.participantId)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color.Theme.primaryBlue)
                    Spacer()
                    Text("\(contrib.discoveryCount) found".localized)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                    Text(String(format: "%.1f", contrib.weightedScore))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.Theme.cardBackground)
        )
    }

    private var gamesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Games".localized)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Color.Theme.primaryBlue)
            ForEach(summary.games, id: \.gameInstanceId) { game in
                VStack(alignment: .leading, spacing: 6) {
                    Text(game.definitionId.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.medium)
                        .foregroundStyle(Color.Theme.primaryBlue)
                    Text("\(game.discoveryCount) discoveries".localized)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.Theme.background)
                )
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.Theme.cardBackground)
        )
    }

    private func firstDiscoveriesSection(projection: DiscoveryCreditProjection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("First discoveries".localized)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Color.Theme.primaryBlue)
            ForEach(projection.targetSummaries.prefix(20), id: \.targetId) { target in
                HStack {
                    Text(target.targetId)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.Theme.primaryBlue)
                    Spacer()
                    Text(target.summaryLabel)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.Theme.cardBackground)
        )
    }

    private var mapRecapPlaceholder: some View {
        HStack {
            Image(systemName: "map.fill")
                .font(.system(.title2))
                .foregroundStyle(Color.Theme.primaryBlue.opacity(0.6))
            Text("Map recap coming soon".localized)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.Theme.cardBackground)
        )
        .accessibilityLabel("Map recap coming soon".localized)
    }
}

#Preview {
    let session = TripSession(
        name: "Preview Trip",
        status: .ended,
        endedAt: Date(),
        participants: [TripParticipant(userId: "user1", role: .owner)]
    )
    let summary = TripSummary(
        sessionId: session.id,
        tripName: session.name,
        status: .ended,
        endedAt: session.endedAt,
        startedAt: nil,
        participantCount: 1,
        gameCount: 1,
        totalDiscoveryCount: 5,
        games: [
            TripSummaryGameItem(
                gameInstanceId: UUID(),
                definitionId: "license_plate",
                discoveryCount: 5,
                startedAt: nil,
                endedAt: nil,
                firstDiscoveries: [],
                completionGoal: 50,
                progressDescription: "5 / 50 US regions"
            )
        ],
        participantContributions: [
            ParticipantContribution(participantId: "user1", discoveryCount: 5, weightedScore: 5.0, firstFindCount: 3)
        ],
        discoveryProjection: nil,
        locationMetadata: nil
    )
    return NavigationStack {
        TripSummaryView(summary: summary, onDismiss: nil)
    }
}
