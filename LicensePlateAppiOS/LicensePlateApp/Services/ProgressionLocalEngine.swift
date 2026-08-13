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

/// One idempotent XP award produced by a completion event (`game_completed` / `game_ended` / `trip_ended`)
/// for one subject. Mirrors a server `ProgressionComponentGrant` from `progressionCore.awardsForEvent`,
/// so the same amounts land locally and on the server and reconciliation is a no-op.
struct ProgressionCompletionComponent: Equatable, Sendable {
    var subjectUserId: String
    var amount: Int
    var reason: XpReasonCode
    /// Game this award belongs to; `nil` for trip-scoped awards.
    var gameInstanceId: UUID?
    var isCompetitiveFirstPlaceFinish: Bool

    init(
        subjectUserId: String,
        amount: Int,
        reason: XpReasonCode,
        gameInstanceId: UUID?,
        isCompetitiveFirstPlaceFinish: Bool = false
    ) {
        self.subjectUserId = subjectUserId
        self.amount = amount
        self.reason = reason
        self.gameInstanceId = gameInstanceId
        self.isCompetitiveFirstPlaceFinish = isCompetitiveFirstPlaceFinish
    }
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

            case .gameCompleted, .gameEnded, .tripEnded:
                guard !serverAppliedEventIds.contains(event.id) else { continue }
                for component in completionComponents(
                    for: event,
                    windowIncludingEvent: window,
                    rosterUserIds: rosterUserIds,
                    gamesById: gamesById,
                    rewards: rewards
                ) where component.subjectUserId == subjectUserId {
                    delta.totalXp += component.amount
                    if component.isCompetitiveFirstPlaceFinish {
                        delta.competitiveFirstPlaceFinishes += 1
                        delta.everCompetitiveFirstPlace = true
                    }
                }

            default:
                break
            }
        }

        return delta
    }

    /// Every XP award a completion event produces, for every subject — the single local mirror of the
    /// server's `awardsForEvent`. Used both for pending totals and for local provisional ledger rows,
    /// so the two projections of the same offline play can never disagree.
    ///
    /// `windowIncludingEvent` must be the session's events in timestamp order up to and including `event`.
    static func completionComponents(
        for event: TripActivityEvent,
        windowIncludingEvent window: [TripActivityEvent],
        rosterUserIds: [String],
        gamesById: [UUID: ProgressionGameSnapshot],
        rewards: ProgressionRewardsConfig = ProgressionRewardsConfigProvider.shared.current
    ) -> [ProgressionCompletionComponent] {
        // Ranking merges in contribution-only ids; the server drops non-members before applying
        // (`uids.filter(memberUserIds.includes)`), so only roster members can be awarded here.
        let rosterSet = Set(rosterUserIds)
        return rawCompletionComponents(
            for: event,
            windowIncludingEvent: window,
            rosterUserIds: rosterUserIds,
            gamesById: gamesById,
            rewards: rewards
        ).filter { rosterSet.contains($0.subjectUserId) }
    }

    private static func rawCompletionComponents(
        for event: TripActivityEvent,
        windowIncludingEvent window: [TripActivityEvent],
        rosterUserIds: [String],
        gamesById: [UUID: ProgressionGameSnapshot],
        rewards: ProgressionRewardsConfig
    ) -> [ProgressionCompletionComponent] {
        switch event.kind {
        case .gameCompleted:
            let gameId = gameInstanceUUID(from: event)
            return rosterUserIds.map {
                ProgressionCompletionComponent(
                    subjectUserId: $0,
                    amount: rewards.xp.gameFullClearBonusXp,
                    reason: .gameFullClear,
                    gameInstanceId: gameId
                )
            }

        case .gameEnded:
            guard let gameId = gameInstanceUUID(from: event) else { return [] }
            var components = rosterUserIds.map {
                ProgressionCompletionComponent(
                    subjectUserId: $0,
                    amount: rewards.xp.gameEndedBonusXp,
                    reason: .gameEnded,
                    gameInstanceId: gameId
                )
            }

            guard let game = gamesById[gameId], game.gameMode == .competitive else { return components }

            let discoveries = TripActivityEventDiscoveryReplay.replay(events: window, gameInstanceFilter: gameId).discoveries
            // FR-28h: placement XP is an OUTCOME — a late replay may not change who placed.
            // The find's own discovery XP is unaffected; only the podium is frozen.
            let outcome = CompetitiveOutcomeEligibility.outcomeInputs(
                discoveries: discoveries,
                mode: game.gameMode,
                teams: game.teams
            )
            // An all-late competitive game has no frozen result: every participant would
            // tie at zero and all of them would take first place.
            guard !outcome.discoveries.isEmpty else { return components }
            let raw = ParticipantContributionBuilder.contributionSummary(
                discoveries: outcome.discoveries,
                credits: outcome.credits
            )
            let roster = rosterUserIds.map { TripParticipant(userId: $0) }
            let merged = TripRosterContributionMerge.merge(roster: roster, contributions: raw)
            let ranked = TripParticipantRanking.rankContributions(merged)
            for entry in ranked {
                let placement: (amount: Int, reason: XpReasonCode)?
                switch entry.rank {
                case 1: placement = (rewards.xp.competitiveFirstPlaceFinishBonusXp, .competitiveFirstPlaceFinish)
                case 2: placement = (rewards.xp.competitiveSecondPlaceFinishBonusXp, .competitiveSecondPlace)
                case 3: placement = (rewards.xp.competitiveThirdPlaceFinishBonusXp, .competitiveThirdPlace)
                default: placement = nil
                }
                guard let placement else { continue }
                components.append(ProgressionCompletionComponent(
                    subjectUserId: entry.contribution.participantId,
                    amount: placement.amount,
                    reason: placement.reason,
                    gameInstanceId: gameId,
                    isCompetitiveFirstPlaceFinish: entry.rank == 1
                ))
            }
            return components

        case .tripEnded:
            var components = rosterUserIds.map {
                ProgressionCompletionComponent(
                    subjectUserId: $0,
                    amount: rewards.xp.tripEndedBonusXp,
                    reason: .tripEnded,
                    gameInstanceId: nil
                )
            }

            let allDiscoveries = TripActivityEventDiscoveryReplay.replay(events: window, gameInstanceFilter: nil).discoveries
            let finders = Set(allDiscoveries.map(\.participantId))
            for uid in rosterUserIds where finders.contains(uid) {
                components.append(ProgressionCompletionComponent(
                    subjectUserId: uid,
                    amount: rewards.xp.tripParticipationBonusXp,
                    reason: .tripParticipation,
                    gameInstanceId: nil
                ))
            }

            guard gamesById.values.contains(where: { $0.gameMode == .competitive }) else { return components }

            // FR-28h: trip-level competitive first place is likewise frozen at trip end,
            // and suppressed entirely when nothing outcome-eligible remains.
            let outcomeDiscoveries = CompetitiveOutcomeEligibility.outcomeEligible(allDiscoveries)
            guard !outcomeDiscoveries.isEmpty else { return components }
            let tripCredits = tripLevelCredits(discoveries: outcomeDiscoveries, gamesById: gamesById)
            let raw = ParticipantContributionBuilder.contributionSummary(
                discoveries: outcomeDiscoveries,
                credits: tripCredits
            )
            let roster = rosterUserIds.map { TripParticipant(userId: $0) }
            let merged = TripRosterContributionMerge.merge(roster: roster, contributions: raw)
            let ranked = TripParticipantRanking.rankContributions(merged)
            for entry in ranked where entry.rank == 1 {
                components.append(ProgressionCompletionComponent(
                    subjectUserId: entry.contribution.participantId,
                    amount: rewards.xp.tripCompetitiveFirstPlaceBonusXp,
                    reason: .tripCompetitiveFirstPlace,
                    gameInstanceId: nil
                ))
            }
            return components

        default:
            return []
        }
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
