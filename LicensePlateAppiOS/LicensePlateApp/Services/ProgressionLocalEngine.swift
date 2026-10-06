//
//  ProgressionLocalEngine.swift
//  LicensePlateApp
//
//  Pure local progression pending delta (parity with `progressionCore.ts` XP amounts). Replays full
//  session events in order; only counts events whose ids are not in `serverAppliedEventIds`.
//  Competitive placement, trip competitive first and trip participation are server-decided
//  (§3.1.1 item 25, OD-17) and are never estimated here.
//

import Foundation

/// One idempotent XP award produced by a completion event (`game_completed` / `game_ended` / `trip_ended`)
/// for one subject — only the outcome-independent ones (`game_full_clear`, `game_ended`, `trip_ended`).
/// Mirrors a server `ProgressionComponentGrant` from `progressionCore.awardsForEvent`, so the same
/// amounts land locally and on the server and reconciliation is a no-op.
struct ProgressionCompletionComponent: Equatable, Sendable {
    var subjectUserId: String
    var amount: Int
    var reason: XpReasonCode
    /// Game this award belongs to; `nil` for trip-scoped awards.
    var gameInstanceId: UUID?
}

enum ProgressionLocalEngine {

    /// Pending progression for one trip session: full ordered events, and the roster the completion
    /// bonuses are paid to.
    static func pendingDeltaForSession(
        sortedSessionEvents: [TripActivityEvent],
        rosterUserIds: [String],
        subjectUserId: String,
        serverAppliedEventIds: Set<String>,
        rewards: ProgressionRewardsConfig = ProgressionRewardsConfigProvider.shared.current
    ) -> ProgressionPendingDelta {
        guard !subjectUserId.isEmpty else { return .zero }

        let orderedEvents = sortedSessionEvents.sorted(by: { $0.timestamp < $1.timestamp })
        let firstFindEventIdByScopedKey = earliestFindEventIdByScopedKey(
            orderedEvents: orderedEvents,
            subjectUserId: subjectUserId
        )

        var delta = ProgressionPendingDelta.zero

        for event in orderedEvents {
            switch event.kind {
            case .regionFound:
                guard !serverAppliedEventIds.contains(event.id) else { continue }
                // The server paid this find off its own `srvrej_` rejection (`LedgerPendingXpTotals`
                // join 2) while the local find is still queued — a callable response that never arrived.
                guard !serverAppliedEventIds.contains(
                    XpServerScopeKey.serverRejectionEventId(forClientEventId: event.id)
                ) else { continue }
                guard let pid = regionFoundParticipantId(event), pid == subjectUserId else { continue }
                guard let key = baseDiscoveryScopedKey(for: event, participantId: pid) else { continue }
                guard firstFindEventIdByScopedKey[key] == event.id else { continue }
                // Pending finds contribute base discovery only; other find bonuses wait for server scopes.
                delta.totalXp += rewards.xp.baseDiscoveryXp
                delta.acceptedRegionFindCount += 1

            case .discoveryRejected:
                guard !serverAppliedEventIds.contains(event.id) else { continue }
                guard serverRejectionPaysFind(event) else { continue }
                guard let pid = regionFoundParticipantId(event), pid == subjectUserId else { continue }
                guard let key = baseDiscoveryScopedKey(for: event, participantId: pid) else { continue }
                // Prefer region_found provisional when both exist; only count the rejection if no accepted find scope.
                if firstFindEventIdByScopedKey[key] != nil { continue }
                delta.totalXp += rewards.xp.baseDiscoveryXp
                delta.acceptedRegionFindCount += 1

            case .gameCompleted, .gameEnded, .tripEnded:
                guard !serverAppliedEventIds.contains(event.id) else { continue }
                for component in completionComponents(
                    for: event,
                    rosterUserIds: rosterUserIds,
                    rewards: rewards
                ) where component.subjectUserId == subjectUserId {
                    delta.totalXp += component.amount
                }

            default:
                break
            }
        }

        return delta
    }

    /// Mirror of the server's `rejectionPaysFind` (`functions/src/progressionCore.ts`): whether a
    /// `discovery_rejected` still pays its find. A late competitive rejection does, and so does
    /// (§3.1.1 item 24) the server's invalid-participant rejection — a find on a trip the server
    /// reads as solo while a partner who has left holds the plate. This device writes the same
    /// invalid-participant reason for a find it refuses at tap time, which earns nothing; only the
    /// server's copy carries `serverResolvedAt`, which no client can send.
    static func serverRejectionPaysFind(_ event: TripActivityEvent) -> Bool {
        guard let payload = event.payload,
              let reason = payload[TripActivityEventPayloadKey.rejectionReason]
        else { return false }
        switch reason {
        case DiscoveryRejectionReason.serverRejectedLateCompetitive.rawValue:
            return true
        case DiscoveryRejectionReason.rejectedInvalidParticipant.rawValue:
            return !(payload[TripActivityEventPayloadKey.serverResolvedAt] ?? "").isEmpty
        default:
            return false
        }
    }

    /// Every XP award a completion event produces on this device, for every roster member — the local
    /// mirror of the OUTCOME-INDEPENDENT half of the server's `awardsForEvent`: `game_full_clear`,
    /// `game_ended` and `trip_ended`. Used both for pending totals and for local provisional ledger
    /// rows, so the two projections of the same offline play can never disagree.
    ///
    /// Competitive placement (1st/2nd/3rd), trip competitive first and trip participation depend on
    /// other players' finds, so they are server-decided (§3.1.1 item 25, OD-17): decided from the
    /// events the server holds when it processes the `game_ended` / `trip_ended`, never minted or
    /// estimated here, and announced by their `xp_grants` when they land.
    static func completionComponents(
        for event: TripActivityEvent,
        rosterUserIds: [String],
        rewards: ProgressionRewardsConfig = ProgressionRewardsConfigProvider.shared.current
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
            return rosterUserIds.map {
                ProgressionCompletionComponent(
                    subjectUserId: $0,
                    amount: rewards.xp.gameEndedBonusXp,
                    reason: .gameEnded,
                    gameInstanceId: gameId
                )
            }

        case .tripEnded:
            return rosterUserIds.map {
                ProgressionCompletionComponent(
                    subjectUserId: $0,
                    amount: rewards.xp.tripEndedBonusXp,
                    reason: .tripEnded,
                    gameInstanceId: nil
                )
            }

        default:
            return []
        }
    }

    /// Sum pending across multiple sessions (e.g. offline play in more than one trip).
    static func pendingDeltaAcrossSessions(
        sessions: [(sortedEvents: [TripActivityEvent], rosterUserIds: [String])],
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
                rewards: rewards
            )
        }
        return acc
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
