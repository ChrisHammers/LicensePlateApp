//
//  TripSummaryShareCardView.swift
//  LicensePlateApp
//
//  Branded RoadTrip Royale share card rasterized for the system share sheet.
//  Laid out at iPhone logical width so type and spacing look natural; height follows content
//  (no forced top/bottom padding). ImageRenderer scales up for a sharp export.
//

import SwiftUI
import UIKit

/// Light branded palette forced for export so the card reads well in any device appearance.
private enum TripSummaryShareCardPalette {
    static let background = Color(red: 0.95, green: 0.94, blue: 0.90)
    static let cardFill = Color(red: 0.87, green: 0.85, blue: 0.80)
    static let primaryBlue = Color(red: 0.18, green: 0.44, blue: 0.64)
    static let softBrown = Color(red: 0.39, green: 0.29, blue: 0.22)
    static let accentYellow = Color(red: 0.78, green: 0.59, blue: 0.0)
}

struct TripSummaryShareCardView: View {
    let summary: TripSummary
    let currentUserId: String?
    let participantDisplayNames: [String: String]

    private let dateFormatter = TripSummaryDateRangeFormatter.shareCardDateFormatter()

    private var uniquePlates: (displayedNames: [String], totalUnique: Int) {
        TripSummaryShareContentBuilder.uniquePlatesFoundByViewer(
            summary: summary,
            viewerUserId: currentUserId
        )
    }

    private var showParticipants: Bool {
        summary.rankedParticipants.count > 1
    }

    private var winners: [RankedParticipantContribution] {
        TripSummaryShareContentBuilder.winners(from: summary)
    }

    var body: some View {
        VStack(spacing: 16) {
            brandHeader

            tripCard

            Text("RoadTrip Royale".localized)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(TripSummaryShareCardPalette.primaryBlue)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .frame(width: TripSummaryShareImageRenderer.logicalWidth)
        .background(TripSummaryShareCardPalette.background)
        .environment(\.colorScheme, .light)
    }

    private var brandHeader: some View {
        VStack(spacing: 10) {
            appIconView
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(TripSummaryShareCardPalette.accentYellow, lineWidth: 2)
                )

            Text("RoadTrip Royale".localized)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(TripSummaryShareCardPalette.primaryBlue)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var appIconView: some View {
        if let uiImage = UIImage(named: "AppIconShare") ?? UIImage(named: "AppIcon") {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                TripSummaryShareCardPalette.primaryBlue
                Image(systemName: "car.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }

    private var tripCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(summary.tripName)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(TripSummaryShareCardPalette.primaryBlue)
                .fixedSize(horizontal: false, vertical: true)

            dateSection

            sectionDivider

            gamesSection

            if showParticipants {
                sectionDivider
                participantsSection
            }

            if uniquePlates.totalUnique > 0 {
                sectionDivider
                uniquePlatesSection
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(TripSummaryShareCardPalette.cardFill)
        )
    }

    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let start = TripSummaryDateRangeFormatter.startDateLine(
                startedAt: summary.startedAt,
                formatter: dateFormatter
            ) {
                Text(start)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(TripSummaryShareCardPalette.softBrown)
            }
            if let end = TripSummaryDateRangeFormatter.endDateLine(
                endedAt: summary.endedAt,
                formatter: dateFormatter
            ) {
                Text(end)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(TripSummaryShareCardPalette.softBrown)
            }
        }
    }

    private var gamesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Games".localized)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(TripSummaryShareCardPalette.primaryBlue)

            if summary.games.isEmpty {
                Text("trip_summary.share.no_games".localized)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(TripSummaryShareCardPalette.softBrown)
            } else {
                ForEach(summary.games, id: \.gameInstanceId) { game in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(TripSummaryShareContentBuilder.gameTypeTitle(game.definitionId))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(TripSummaryShareCardPalette.primaryBlue)
                        Text("\(game.discoveryCount) discoveries".localized)
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundStyle(TripSummaryShareCardPalette.softBrown)
                        if let progress = game.progressDescription, !progress.isEmpty {
                            Text(progress)
                                .font(.system(size: 13, weight: .regular, design: .rounded))
                                .foregroundStyle(TripSummaryShareCardPalette.softBrown)
                        }
                    }
                }
            }
        }
    }

    private var participantsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Participants".localized)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(TripSummaryShareCardPalette.primaryBlue)

            if !winners.isEmpty {
                Text(winnerLine)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(TripSummaryShareCardPalette.accentYellow)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(summary.rankedParticipants) { row in
                let c = row.contribution
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if summary.hasCompetitiveGame {
                        Text("Rank #%d".localized(row.rank))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(TripSummaryShareCardPalette.primaryBlue)
                            .frame(minWidth: 52, alignment: .leading)
                    }
                    Text(displayName(for: c.participantId))
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(TripSummaryShareCardPalette.primaryBlue)
                        .lineLimit(2)
                    Spacer(minLength: 6)
                    Text("trip_summary.share.participant_score %@ %@".localized(
                        "\(c.discoveryCount)",
                        String(format: "%.1f", c.weightedScore)
                    ))
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(TripSummaryShareCardPalette.softBrown)
                }
            }
        }
    }

    private var winnerLine: String {
        let names = winners.map { displayName(for: $0.contribution.participantId) }
        let topScore = winners.first.map { String(format: "%.1f", $0.contribution.weightedScore) } ?? "0"
        if winners.count == 1 {
            return "trip_summary.share.winner %@ %@".localized(names[0], topScore)
        }
        return "trip_summary.share.winners_tied %@ %@".localized(
            names.joined(separator: ", "),
            topScore
        )
    }

    private var uniquePlatesSection: some View {
        let plates = uniquePlates
        return VStack(alignment: .leading, spacing: 8) {
            Text("trip_summary.share.my_unique_zones %d".localized(plates.totalUnique))
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(TripSummaryShareCardPalette.primaryBlue)

            Text(plates.displayedNames.joined(separator: ", "))
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(TripSummaryShareCardPalette.softBrown)
                .fixedSize(horizontal: false, vertical: true)

            let overflow = plates.totalUnique - plates.displayedNames.count
            if overflow > 0 {
                Text("trip_summary.share.more_zones %d".localized(overflow))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(TripSummaryShareCardPalette.softBrown)
            }
        }
    }

    private var sectionDivider: some View {
        Divider()
            .background(TripSummaryShareCardPalette.softBrown.opacity(0.35))
    }

    private func displayName(for participantId: String) -> String {
        let raw = participantDisplayNames[participantId] ?? participantId
        return ParticipantDisplayName.decorated(
            raw,
            userId: participantId,
            currentUserId: currentUserId
        )
    }
}

@MainActor
enum TripSummaryShareImageRenderer {
    /// iPhone logical width so layout/type reads like an on-device screenshot.
    static let logicalWidth: CGFloat = 390
    /// Retina scale for export sharpness (390 × 3 ≈ 1170 px wide).
    static let exportScale: CGFloat = 3

    static func render(
        summary: TripSummary,
        currentUserId: String?,
        participantDisplayNames: [String: String]
    ) -> UIImage? {
        let view = TripSummaryShareCardView(
            summary: summary,
            currentUserId: currentUserId,
            participantDisplayNames: participantDisplayNames
        )
        let renderer = ImageRenderer(content: view)
        renderer.scale = exportScale
        renderer.proposedSize = ProposedViewSize(width: logicalWidth, height: nil)
        return renderer.uiImage
    }
}

#Preview("Share card — solo") {
    TripSummaryShareCardView(
        summary: PreviewSummaryFixtures.tripSummarySolo(),
        currentUserId: PreviewConstants.userId1,
        participantDisplayNames: [PreviewConstants.userId1: "Alex"]
    )
}

#Preview("Share card — competitive") {
    TripSummaryShareCardView(
        summary: PreviewSummaryFixtures.tripSummaryCompetitiveTied(),
        currentUserId: PreviewConstants.userId1,
        participantDisplayNames: [
            PreviewConstants.userId1: "Alex",
            PreviewConstants.userId2: "Blake"
        ]
    )
}
