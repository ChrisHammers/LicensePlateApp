//
//  TripSummaryShareContentBuilder.swift
//  LicensePlateApp
//
//  Pure projection helpers for the branded trip summary share card.
//

import Foundation

enum TripSummaryShareContentBuilder {
    /// Max unique plate names listed on the share card before “+N more”.
    static let plateListCap = 30

    /// Unique zones the viewer found (union across games), sorted by display name.
    static func uniquePlatesFoundByViewer(
        summary: TripSummary,
        viewerUserId: String?
    ) -> (displayedNames: [String], totalUnique: Int) {
        guard let viewerUserId, !viewerUserId.isEmpty else {
            return ([], 0)
        }
        guard let projection = summary.discoveryProjection else {
            return ([], 0)
        }

        var seen = Set<String>()
        var orderedIds: [String] = []
        for target in projection.targetSummaries {
            guard target.allFinderParticipantIds.contains(viewerUserId) else { continue }
            if seen.insert(target.targetId).inserted {
                orderedIds.append(target.targetId)
            }
        }

        let names = orderedIds
            .map { regionDisplayName(for: $0) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        let displayed = Array(names.prefix(plateListCap))
        return (displayed, names.count)
    }

    static func regionDisplayName(for targetId: String) -> String {
        PlateRegion.all.first(where: { $0.id == targetId })?.name ?? targetId
    }

    static func gameTypeTitle(_ definitionId: String) -> String {
        GameType(rawValue: definitionId)?.displayName
            ?? definitionId.replacingOccurrences(of: "_", with: " ").capitalized
    }

    /// Rank-1 participants (competition ranking). Empty when fewer than 2 participants.
    static func winners(from summary: TripSummary) -> [RankedParticipantContribution] {
        guard summary.rankedParticipants.count > 1 else { return [] }
        return summary.rankedParticipants.filter { $0.rank == 1 }
    }
}
