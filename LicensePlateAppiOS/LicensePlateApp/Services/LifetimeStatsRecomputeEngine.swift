//
//  LifetimeStatsRecomputeEngine.swift
//  LicensePlateApp
//
//  Pure, Sendable aggregation — runs off the MainActor. See `LifetimeStatsSpec`.
//

import Foundation

enum LifetimeStatsRecomputeEngine {

    static func compute(_ input: LifetimeStatsRecomputeInput) throws -> UserLifetimeStats {
        var totalCompletedTrips = 0
        var totalGamesPlayed = 0
        var totalDiscoveries = 0
        var totalWeightedScore: Double = 0
        var familyOnlyTripsCount = 0
        var friendsOnlyTripsCount = 0
        var mixedFriendsFamilyTripsCount = 0
        var entireFamilyTripsCount = 0
        let now = Date()

        for trip in input.trips {
            let session = trip.session.toTripSession()
            guard session.status == .ended else { continue }

            guard let selfRow = session.participants.first(where: { $0.userId == input.subjectUserId }) else {
                continue
            }
            if selfRow.leftAt != nil {
                continue
            }

            let games = trip.games.map { $0.toGameInstance() }
            let summary = TripSummaryBuilder.build(session: session, games: games, discoveries: trip.discoveries)

            totalCompletedTrips += 1
            totalGamesPlayed += summary.gameCount

            if let row = summary.rankedParticipants.first(where: { $0.contribution.participantId == input.subjectUserId }) {
                totalDiscoveries += row.contribution.discoveryCount
                totalWeightedScore += row.contribution.weightedScore
            }

            let activeRoster = session.participants.filter { $0.leftAt == nil }
            let bucket = LifetimeStatsSocialClassification.classifySocialTrip(
                activeParticipants: activeRoster,
                subjectUserId: input.subjectUserId,
                familyMemberUserIds: input.familyMemberUserIds,
                friendUserIds: input.friendUserIds
            )
            switch bucket {
            case .familyOnly:
                familyOnlyTripsCount += 1
            case .friendsOnly:
                friendsOnlyTripsCount += 1
            case .mixed:
                mixedFriendsFamilyTripsCount += 1
            case .neither:
                break
            }

            if LifetimeStatsSocialClassification.isEntireFamilyTrip(
                activeParticipants: activeRoster,
                familyMemberUserIds: input.familyMemberUserIds
            ) {
                entireFamilyTripsCount += 1
            }
        }

        return UserLifetimeStats(
            totalCompletedTrips: totalCompletedTrips,
            totalGamesPlayed: totalGamesPlayed,
            totalDiscoveries: totalDiscoveries,
            totalWeightedScore: totalWeightedScore,
            familyOnlyTripsCount: familyOnlyTripsCount,
            friendsOnlyTripsCount: friendsOnlyTripsCount,
            mixedFriendsFamilyTripsCount: mixedFriendsFamilyTripsCount,
            entireFamilyTripsCount: entireFamilyTripsCount,
            lastComputedAt: now
        )
    }
}

private extension LifetimeStatsSessionSnapshot {
    func toTripSession() -> TripSession {
        let status = TripSessionState(rawValue: statusRaw) ?? .ended
        return TripSession(
            id: id,
            name: name,
            status: status,
            createdAt: createdAt,
            createdBy: createdBy,
            startedAt: startedAt,
            endedAt: endedAt,
            endedBy: endedBy,
            participants: participants,
            riskFlags: riskFlags
        )
    }
}

private extension LifetimeStatsGameSnapshot {
    func toGameInstance() -> GameInstance {
        GameInstance(
            id: id,
            definitionId: definitionId,
            sessionId: sessionId,
            startedAt: startedAt,
            endedAt: endedAt,
            ruleSet: ruleSet,
            commonConfig: commonConfig,
            gameSpecificPayloadType: gameSpecificPayloadType,
            gameSpecificPayloadVersion: gameSpecificPayloadVersion,
            gameSpecificPayloadData: gameSpecificPayloadData,
            teams: teams,
            fairnessUiLastAckAt: fairnessUiLastAckAt
        )
    }
}
