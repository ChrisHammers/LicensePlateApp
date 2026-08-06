//
//  TripSummaryShareContentBuilderTests.swift
//  LicensePlateAppTests
//

import Foundation
import Testing
@testable import LicensePlateApp

struct TripSummaryShareContentBuilderTests {

    @Test func uniquePlatesFoundByViewerDedupesAcrossGamesAndCaps() {
        let viewer = "viewer-1"
        let other = "other-2"
        var targets: [TargetDiscoverySummary] = []
        // Same region found by viewer in two games — counts once.
        targets.append(TargetDiscoverySummary(
            gameInstanceId: UUID(),
            targetId: "us-ca",
            firstFinderParticipantId: viewer,
            allFinderParticipantIds: [viewer],
            summaryLabel: "California"
        ))
        targets.append(TargetDiscoverySummary(
            gameInstanceId: UUID(),
            targetId: "us-ca",
            firstFinderParticipantId: other,
            allFinderParticipantIds: [viewer, other],
            summaryLabel: "California"
        ))
        targets.append(TargetDiscoverySummary(
            gameInstanceId: UUID(),
            targetId: "us-tx",
            firstFinderParticipantId: viewer,
            allFinderParticipantIds: [viewer],
            summaryLabel: "Texas"
        ))
        // Other finder only — excluded.
        targets.append(TargetDiscoverySummary(
            gameInstanceId: UUID(),
            targetId: "us-ny",
            firstFinderParticipantId: other,
            allFinderParticipantIds: [other],
            summaryLabel: "New York"
        ))

        var summary = PreviewSummaryFixtures.tripSummarySolo()
        summary.discoveryProjection = DiscoveryCreditProjection(
            participantScores: [],
            targetSummaries: targets
        )

        let result = TripSummaryShareContentBuilder.uniquePlatesFoundByViewer(
            summary: summary,
            viewerUserId: viewer
        )
        #expect(result.totalUnique == 2)
        #expect(result.displayedNames.count == 2)
        #expect(result.displayedNames.contains("California"))
        #expect(result.displayedNames.contains("Texas"))
        #expect(!result.displayedNames.contains("New York"))
    }

    @Test func uniquePlatesEmptyWithoutViewerOrProjection() {
        var summary = PreviewSummaryFixtures.tripSummarySolo()
        summary.discoveryProjection = nil
        let emptyViewer = TripSummaryShareContentBuilder.uniquePlatesFoundByViewer(
            summary: summary,
            viewerUserId: nil
        )
        #expect(emptyViewer.totalUnique == 0)

        summary.discoveryProjection = DiscoveryCreditProjection(participantScores: [], targetSummaries: [])
        let emptyProjection = TripSummaryShareContentBuilder.uniquePlatesFoundByViewer(
            summary: summary,
            viewerUserId: "viewer-1"
        )
        #expect(emptyProjection.totalUnique == 0)
    }

    @Test func winnersEmptyForSoloAndIncludesRankOneForMulti() {
        let solo = PreviewSummaryFixtures.tripSummarySolo()
        #expect(TripSummaryShareContentBuilder.winners(from: solo).isEmpty)

        let multi = PreviewSummaryFixtures.tripSummaryCompetitiveTied()
        let winners = TripSummaryShareContentBuilder.winners(from: multi)
        #expect(!winners.isEmpty)
        #expect(winners.allSatisfy { $0.rank == 1 })
    }

    @Test func plateListCapAppliesWhenManyZones() {
        let viewer = "viewer-1"
        var targets: [TargetDiscoverySummary] = []
        for index in 0..<40 {
            targets.append(TargetDiscoverySummary(
                gameInstanceId: UUID(),
                targetId: "zone-\(index)",
                firstFinderParticipantId: viewer,
                allFinderParticipantIds: [viewer],
                summaryLabel: "Zone \(index)"
            ))
        }
        var summary = PreviewSummaryFixtures.tripSummarySolo()
        summary.discoveryProjection = DiscoveryCreditProjection(
            participantScores: [],
            targetSummaries: targets
        )
        let result = TripSummaryShareContentBuilder.uniquePlatesFoundByViewer(
            summary: summary,
            viewerUserId: viewer
        )
        #expect(result.totalUnique == 40)
        #expect(result.displayedNames.count == TripSummaryShareContentBuilder.plateListCap)
    }
}
