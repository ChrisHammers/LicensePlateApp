//
//  ProgressionLocalEngine.swift
//  LicensePlateApp
//
//  Pure local progression pending delta (parity with `progressionCore.ts` XP amounts and
//  `TripParticipantRanking` for competitive places). Replays full session events in order; only counts
//  events whose ids are not in `serverAppliedEventIds`.
//

import Foundation

/// Minimal game metadata for local progression (mirrors server `commonConfig` + teams).
struct ProgressionGameSnapshot: Sendable {
    var id: UUID
    var gameMode: GameMode
    var teams: [TripTeam]
}

enum ProgressionLocalEngine {

    /// Pending progression for one trip session: full ordered events, roster for merge, games by id.
    static func pendingDeltaForSession(
        sortedSessionEvents: [TripActivityEvent],
        rosterUserIds: [String],
        subjectUserId: String,
        serverAppliedEventIds: Set<String>,
        gamesById: [UUID: ProgressionGameSnapshot],
        rewards: ProgressionRewardsConfig = ProgressionRewardsConfigProvider.shared.current
    ) -> ProgressionPendingDelta {
        guard !subjectUserId.isEmpty else { return .zero }

        let orderedEvents = sortedSessionEvents.sorted(by: { $0.timestamp < $1.timestamp })
        let firstFindEventIdByScopedKey = earliestFindEventIdByScopedKey(
            orderedEvents: orderedEvents,
            subjectUserId: subjectUserId
        )

        var window: [TripActivityEvent] = []
        var delta = ProgressionPendingDelta.zero
        let hasCompetitiveGame = gamesById.values.contains { $0.gameMode == .competitive }

        for event in orderedEvents {
            window.append(event)

            switch event.kind {
            case .regionFound:
                guard !serverAppliedEventIds.contains(event.id) else { continue }
                guard let pid = regionFoundParticipantId(event), pid == subjectUserId else { continue }
                guard let key = baseDiscoveryScopedKey(for: event, participantId: pid) else { continue }
                guard firstFindEventIdByScopedKey[key] == event.id else { continue }
                // Pending finds contribute base discovery only; other find bonuses wait for server scopes.
                delta.totalXp += rewards.xp.baseDiscoveryXp
                delta.acceptedRegionFindCount += 1

            case .discoveryRejected:
                guard !serverAppliedEventIds.contains(event.id) else { continue }
                guard let reason = event.payload?[TripActivityEventPayloadKey.rejectionReason],
                      reason == DiscoveryRejectionReason.serverRejectedLateCompetitive.rawValue
                else { continue }
                guard let pid = regionFoundParticipantId(event), pid == subjectUserId else { continue }
                guard let key = baseDiscoveryScopedKey(for: event, participantId: pid) else { continue }
                // Prefer region_found provisional when both exist; only count late reject if no accepted find scope.
                if firstFindEventIdByScopedKey[key] != nil { continue }
                delta.totalXp += rewards.xp.baseDiscoveryXp
                delta.acceptedRegionFindCount += 1

            case .gameCompleted:
                guard !serverAppliedEventIds.contains(event.id) else { continue }
                guard rosterUserIds.contains(subjectUserId) else { continue }
                delta.totalXp += rewards.xp.gameFullClearBonusXp

            case .gameEnded:
                guard !serverAppliedEventIds.contains(event.id) else { continue }
                guard let gameId = gameInstanceUUID(from: event) else { continue }
                guard rosterUserIds.contains(subjectUserId) else { continue }
                delta.totalXp += rewards.xp.gameEndedBonusXp

                guard let game = gamesById[gameId], game.gameMode == .competitive else { continue }

                let discoveries = TripActivityEventDiscoveryReplay.replay(events: window, gameInstanceFilter: gameId).discoveries
                let byTarget = Dictionary(grouping: discoveries, by: \.targetId)
                let credits = DiscoveryRulesEngine.creditsForDiscoveries(
                    mode: game.gameMode,
                    discoveriesByTarget: byTarget,
                    teams: game.teams
                )
                let raw = ParticipantContributionBuilder.contributionSummary(discoveries: discoveries, credits: credits)
                let roster = rosterUserIds.map { TripParticipant(userId: $0) }
                let merged = TripRosterContributionMerge.merge(roster: roster, contributions: raw)
                let ranked = TripParticipantRanking.rankContributions(merged)
                guard let subjectRank = ranked.first(where: { $0.contribution.participantId == subjectUserId })?.rank else {
                    continue
                }
                switch subjectRank {
                case 1:
                    delta.totalXp += rewards.xp.competitiveFirstPlaceFinishBonusXp
                    delta.competitiveFirstPlaceFinishes += 1
                    delta.everCompetitiveFirstPlace = true
                case 2:
                    delta.totalXp += rewards.xp.competitiveSecondPlaceFinishBonusXp
                case 3:
                    delta.totalXp += rewards.xp.competitiveThirdPlaceFinishBonusXp
                default:
                    break
                }

            case .tripEnded:
                guard !serverAppliedEventIds.contains(event.id) else { continue }
                guard rosterUserIds.contains(subjectUserId) else { continue }
                delta.totalXp += rewards.xp.tripEndedBonusXp

                let allDiscoveries = TripActivityEventDiscoveryReplay.replay(events: window, gameInstanceFilter: nil).discoveries
                if allDiscoveries.contains(where: { $0.participantId == subjectUserId }) {
                    delta.totalXp += rewards.xp.tripParticipationBonusXp
                }

                if hasCompetitiveGame {
                    let tripCredits = tripLevelCredits(
                        discoveries: allDiscoveries,
                        gamesById: gamesById
                    )
                    let raw = ParticipantContributionBuilder.contributionSummary(
                        discoveries: allDiscoveries,
                        credits: tripCredits
                    )
                    let roster = rosterUserIds.map { TripParticipant(userId: $0) }
                    let merged = TripRosterContributionMerge.merge(roster: roster, contributions: raw)
                    let ranked = TripParticipantRanking.rankContributions(merged)
                    let rankOnes = Set(ranked.filter { $0.rank == 1 }.map(\.contribution.participantId))
                    if rankOnes.contains(subjectUserId) {
                        delta.totalXp += rewards.xp.tripCompetitiveFirstPlaceBonusXp
                    }
                }

            default:
                break
            }
        }

        return delta
    }

    /// Sum pending across multiple sessions (e.g. offline play in more than one trip).
    static func pendingDeltaAcrossSessions(
        sessions: [(sortedEvents: [TripActivityEvent], rosterUserIds: [String], gamesById: [UUID: ProgressionGameSnapshot])],
        subjectUserId: String,
        serverAppliedEventIds: Set<String>,
        rewards: ProgressionRewardsConfig = ProgressionRewardsConfigProvider.shared.current
    ) -> ProgressionPendingDelta {
        var acc = ProgressionPendingDelta.zero
        for session in sessions {
            acc = acc + pendingDeltaForSession(
                sortedSessionEvents: session.sortedEvents,
                rosterUserIds: session.rosterUserIds,
                subjectUserId: subjectUserId,
                serverAppliedEventIds: serverAppliedEventIds,
                gamesById: session.gamesById,
                rewards: rewards
            )
        }
        return acc
    }

    private static func tripLevelCredits(
        discoveries: [GameDiscovery],
        gamesById: [UUID: ProgressionGameSnapshot]
    ) -> [GameCredit] {
        var credits: [GameCredit] = []
        let byGame = Dictionary(grouping: discoveries, by: \.gameInstanceId)
        for (gameId, gameDisco) in byGame {
            guard let game = gamesById[gameId] else { continue }
            let byTarget = Dictionary(grouping: gameDisco, by: \.targetId)
            credits.append(contentsOf: DiscoveryRulesEngine.creditsForDiscoveries(
                mode: game.gameMode,
                discoveriesByTarget: byTarget,
                teams: game.teams
            ))
        }
        return credits
    }

    private static func regionFoundParticipantId(_ event: TripActivityEvent) -> String? {
        if let p = event.payload?[TripActivityEventPayloadKey.participantId], !p.isEmpty {
            return p
        }
        if let a = event.actorId, !a.isEmpty {
            return a
        }
        return nil
    }

    private static func gameInstanceUUID(from event: TripActivityEvent) -> UUID? {
        guard let s = event.payload?[TripActivityEventPayloadKey.gameInstanceId] else { return nil }
        return UUID(uuidString: s)
    }

    private static func baseDiscoveryScopedKey(for event: TripActivityEvent, participantId: String) -> String? {
        guard let gameId = gameInstanceUUID(from: event) else { return nil }
        guard let regionId = event.payload?[TripActivityEventPayloadKey.regionId], !regionId.isEmpty else { return nil }
        return XpLedgerKeyBuilder.uniquenessKey(
            userId: participantId,
            sessionId: event.sessionId,
            gameInstanceId: gameId,
            itemId: regionId,
            xpCategory: .baseRegionDiscovery
        ).storageString
    }

    private static func earliestFindEventIdByScopedKey(
        orderedEvents: [TripActivityEvent],
        subjectUserId: String
    ) -> [String: String] {
        var firstByKey: [String: String] = [:]
        for event in orderedEvents where event.kind == .regionFound {
            guard let pid = regionFoundParticipantId(event), pid == subjectUserId else { continue }
            guard let key = baseDiscoveryScopedKey(for: event, participantId: pid) else { continue }
            if firstByKey[key] == nil {
                firstByKey[key] = event.id
            }
        }
        return firstByKey
    }
}

extension GameInstance {
    var progressionGameSnapshot: ProgressionGameSnapshot {
        ProgressionGameSnapshot(id: id, gameMode: commonConfig.gameMode, teams: teams)
    }
}
