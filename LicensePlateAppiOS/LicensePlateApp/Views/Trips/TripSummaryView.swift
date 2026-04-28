//
//  TripSummaryView.swift
//  LicensePlateApp
//
//  Step 07 — Rich trip summary: progress, participant contributions, per-game summary, first discoveries.
//

import SwiftUI

struct TripSummaryView: View {
    let summary: TripSummary
    let currentUserId: String?
    var onDismiss: (() -> Void)?

    @State private var participantDisplayNames: [String: String] = [:]
    @State private var showAllDiscoveryHighlights = false

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    /// Collapsed row count for discovery highlights (expand via control below).
    private var discoveryHighlightsCollapsedLimit: Int { 20 }

    var body: some View {
        AppBackgroundView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerSection
                    statsSection
                    recapIncompleteBanner
                    if !summary.rankedParticipants.isEmpty {
                        participantsSection
                    }
                    if !summary.games.isEmpty {
                        gamesSection
                    }
                    if let projection = summary.discoveryProjection, !projection.targetSummaries.isEmpty {
                        firstDiscoveriesSection(projection: projection)
                    }
                    if !summary.xpRecapLines.isEmpty {
                        xpRecapSection
                    }
                    if summary.locationMetadata != nil && !summary.locationMetadata!.isEmpty {
                        mapRecapPlaceholder
                    }
                }
                .padding()
            }
        }
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
        .task { await loadParticipantDisplayNames() }
    }

    /// Collects all participant IDs from the summary and fetches display names from UserRepository.
    private func loadParticipantDisplayNames() async {
        var ids: Set<String> = Set(summary.rankedParticipants.map(\.contribution.participantId))
        if let projection = summary.discoveryProjection {
            for target in projection.targetSummaries {
                if let first = target.firstFinderParticipantId { ids.insert(first) }
                ids.formUnion(target.allFinderParticipantIds)
            }
        }
        participantDisplayNames = await UserRepository.shared.displayNames(forUserIds: ids)
    }

    /// Region or discovery display name for a target id (e.g. "us-ca" -> "California").
    private func regionName(for targetId: String) -> String {
        PlateRegion.all.first(where: { $0.id == targetId })?.name ?? targetId
    }

    private func displayName(for participantId: String) -> String {
        let name = participantDisplayNames[participantId] ?? participantId
        guard let currentUserId, !currentUserId.isEmpty, participantId == currentUserId else {
            return name
        }
        return "\(name) [You]"
    }

    private func decoratedParticipantDisplayNames(for participantIds: [String]) -> [String: String] {
        var names: [String: String] = [:]
        for participantId in participantIds {
            names[participantId] = displayName(for: participantId)
        }
        return names
    }

    /// Resolved "found by" label using display names when available.
    private func foundByLabel(for target: TargetDiscoverySummary) -> String {
        if let firstId = target.firstFinderParticipantId, target.allFinderParticipantIds.count == 1 {
            return "Found by %@".localized(displayName(for: firstId))
        }
        if target.allFinderParticipantIds.count > 1 {
            let mode: GameMode? = {
                guard let gid = target.gameInstanceId else { return nil }
                return summary.games.first(where: { $0.gameInstanceId == gid })?.gameMode
            }()
            let effectiveMode = mode ?? .collaborative
            if GameModeRulesEngine.displayFirstFinderProminently(mode: effectiveMode),
               let firstId = target.firstFinderParticipantId {
                return "Found by %@".localized(displayName(for: firstId))
            }
            if effectiveMode == .competitive {
                return "%d finders".localized(target.allFinderParticipantIds.count)
            }
            return ParticipantDiscoveryResolver.collaborativeMultiFinderDisplayLabel(
                orderedParticipantIds: target.allFinderParticipantIds,
                displayNames: decoratedParticipantDisplayNames(for: target.allFinderParticipantIds)
            )
        }
        return target.summaryLabel
    }

    /// Secondary line when the same region can appear for more than one game on this trip.
    private func gameContextLabel(for target: TargetDiscoverySummary) -> String? {
        guard summary.gameCount > 1, let gid = target.gameInstanceId,
              let item = summary.games.first(where: { $0.gameInstanceId == gid }) else { return nil }
        return gameTypeTitle(item.definitionId)
    }

    private func gameTypeTitle(_ definitionId: String) -> String {
        GameType(rawValue: definitionId)?.displayName
            ?? definitionId.replacingOccurrences(of: "_", with: " ").capitalized
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
            VStack(alignment: .leading, spacing: 4) {
                Text("Trip participation: %@".localized(summary.tripMode.localizedDisplayName))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                    .accessibilityLabel("Trip participation".localized + ", " + summary.tripMode.localizedDisplayName)
                Text("Trip status: %@".localized(tripStatusLabel(summary.status)))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                    .accessibilityLabel("Trip status".localized + ", " + tripStatusLabel(summary.status))
            }
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
        .accessibilityLabel(
            "Overview".localized
                + ", \(summary.tripMode.localizedDisplayName)"
                + ", \(tripStatusLabel(summary.status))"
                + ", \(summary.participantCount) participants, \(summary.gameCount) games, \(summary.totalDiscoveryCount) discoveries"
        )
    }

    @ViewBuilder
    private var recapIncompleteBanner: some View {
        if summary.unassignedDiscoveryCount > 0 {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .font(.system(.title3))
                    .foregroundStyle(Color.Theme.primaryBlue.opacity(0.75))
                    .accessibilityHidden(true)
                Text("Some discoveries are not tied to a game on this recap.".localized)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.Theme.cardBackground)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Some discoveries are not tied to a game on this recap.".localized)
        }
    }

    private func tripStatusLabel(_ status: TripSessionState) -> String {
        switch status {
        case .created: return "Created".localized
        case .active: return "Active".localized
        case .ended: return "Ended".localized
        case .cancelled: return "Cancelled".localized
        }
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

    private func xpRecapLineAccessibility(_ line: XpFeedProjection) -> String {
        var parts: [String] = [line.title]
        if let s = line.subtitle, !s.isEmpty { parts.append(s) }
        parts.append(line.xpDisplayText)
        return parts.joined(separator: ", ")
    }

    private var xpRecapSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("tripSummary.xp_recap.title".localized)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Color.Theme.primaryBlue)
                .accessibilityAddTraits(.isHeader)
            Text("tripSummary.xp_recap.subtitle".localized)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(summary.xpRecapLines) { line in
                VStack(alignment: .leading, spacing: 4) {
                    Text(line.title)
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                    if let sub = line.subtitle, !sub.isEmpty {
                        Text(sub)
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                    }
                    Text(line.xpDisplayText)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                    Text(line.state == .provisional ? "tripSummary.xp_recap.state.provisional".localized : "tripSummary.xp_recap.state.final".localized)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown.opacity(0.85))
                }
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(xpRecapLineAccessibility(line))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.Theme.cardBackground)
        )
    }

    private var participantsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Participant contributions".localized)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Color.Theme.primaryBlue)
            if summary.gameCount > 1 {
                Text("Scores and finds combine all games on this trip.".localized)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Scores and finds combine all games on this trip.".localized)
            }
            ForEach(summary.rankedParticipants) { row in
                let c = row.contribution
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if summary.hasCompetitiveGame {
                        Text("Rank #%d".localized(row.rank))
                            .font(.system(.caption, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.Theme.primaryBlue)
                            .frame(minWidth: 56, alignment: .leading)
                        if row.isTiedOnScore {
                            Text("Tied".localized)
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(Color.Theme.softBrown)
                        }
                    }
                    Text(displayName(for: c.participantId))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color.Theme.primaryBlue)
                    Spacer(minLength: 4)
                    if summary.hasCompetitiveGame {
                        Text("%d first finds".localized(c.firstFindCount))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                    }
                    Text("\(c.discoveryCount) found".localized)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                    Text(String(format: "%.1f", c.weightedScore))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(participantRowAccessibilityLabel(row: row))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.Theme.cardBackground)
        )
    }

    private func participantRowAccessibilityLabel(row: RankedParticipantContribution) -> String {
        let c = row.contribution
        let name = displayName(for: c.participantId)
        var parts: [String] = [name]
        if summary.hasCompetitiveGame {
            parts.append("Rank #%d".localized(row.rank))
            if row.isTiedOnScore { parts.append("Tied".localized) }
            parts.append("%d first finds".localized(c.firstFindCount))
        }
        parts.append("\(c.discoveryCount) found".localized)
        parts.append(String(format: "%.1f", c.weightedScore))
        return parts.joined(separator: ", ")
    }

    private var gamesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Games".localized)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Color.Theme.primaryBlue)
            ForEach(summary.games, id: \.gameInstanceId) { game in
                VStack(alignment: .leading, spacing: 6) {
                    Text(gameTypeTitle(game.definitionId))
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.medium)
                        .foregroundStyle(Color.Theme.primaryBlue)
                    Text("\(game.discoveryCount) discoveries".localized)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                    if let progress = game.progressDescription {
                        Text(progress)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                    }
                    Text("Game mode: %@".localized(game.gameMode.localizedDisplayName))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                        .accessibilityLabel("Game mode".localized + ", " + game.gameMode.localizedDisplayName)
                    if let teams = game.teamSummary {
                        Text("Teams: %@".localized(teams))
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                            .accessibilityLabel("Teams".localized + ", " + teams)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.Theme.background)
                )
                .accessibilityElement(children: .combine)
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
        let summaries = projection.targetSummaries
        let limit = discoveryHighlightsCollapsedLimit
        let isTruncating = summaries.count > limit && !showAllDiscoveryHighlights
        let visible: [TargetDiscoverySummary] = isTruncating ? Array(summaries.prefix(limit)) : summaries

        return VStack(alignment: .leading, spacing: 12) {
            Text("Discovery highlights".localized)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Color.Theme.primaryBlue)
                .accessibilityAddTraits(.isHeader)
            if summary.gameCount > 1 {
                Text("Scores and finds combine all games on this trip.".localized)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Scores and finds combine all games on this trip.".localized)
            }
            ForEach(visible) { target in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(regionName(for: target.targetId))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.Theme.primaryBlue)
                        Spacer()
                        Text(foundByLabel(for: target))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                    }
                    if let gameLabel = gameContextLabel(for: target) {
                        Text(gameLabel)
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown.opacity(0.9))
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(discoveryHighlightAccessibilityLabel(for: target))
            }
            if summaries.count > limit {
                Button {
                    FeedbackService.shared.buttonTap()
                    showAllDiscoveryHighlights.toggle()
                } label: {
                    Text(
                        isTruncating
                            ? "Show all discovery highlights".localized
                            : "Show fewer discovery highlights".localized
                    )
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.medium)
                    .foregroundStyle(Color.Theme.primaryBlue)
                }
                .accessibilityHint(
                    isTruncating
                        ? "More discovery highlights are hidden. Expand to show all.".localized
                        : "Collapses the discovery highlights list.".localized
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

    private func discoveryHighlightAccessibilityLabel(for target: TargetDiscoverySummary) -> String {
        var parts: [String] = [regionName(for: target.targetId), foundByLabel(for: target)]
        if let gameLabel = gameContextLabel(for: target) {
            parts.append("Game".localized + ": " + gameLabel)
        }
        return parts.joined(separator: ", ")
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

#Preview("Solo summary") {
    NavigationStack {
        TripSummaryView(summary: PreviewSummaryFixtures.tripSummarySolo(), currentUserId: nil, onDismiss: nil)
    }
}

#Preview("Multi-game summary") {
    NavigationStack {
        TripSummaryView(summary: PreviewSummaryFixtures.tripSummaryMultiGame(), currentUserId: nil, onDismiss: nil)
    }
}

#Preview("Discovery highlights — same region, two games") {
    NavigationStack {
        TripSummaryView(summary: PreviewSummaryFixtures.tripSummaryDuplicateRegionAcrossGames(), currentUserId: nil, onDismiss: nil)
    }
}

#Preview("Collaborative — two finders, one region") {
    NavigationStack {
        TripSummaryView(summary: PreviewSummaryFixtures.tripSummaryCollaborativeTwoFindersOneRegion(), currentUserId: nil, onDismiss: nil)
    }
}

#Preview("Competitive — tied standings") {
    NavigationStack {
        TripSummaryView(summary: PreviewSummaryFixtures.tripSummaryCompetitiveTied(), currentUserId: nil, onDismiss: nil)
    }
}

#Preview("Collaborative — three finders, one region") {
    NavigationStack {
        TripSummaryView(summary: PreviewSummaryFixtures.tripSummaryCollaborativeThreeFindersOneRegion(), currentUserId: nil, onDismiss: nil)
    }
}

#Preview("Discovery highlights — show all control") {
    NavigationStack {
        TripSummaryView(summary: PreviewSummaryFixtures.tripSummaryManyDiscoveryHighlights(), currentUserId: nil, onDismiss: nil)
    }
}
