//
//  GameplayXpSyncSupport.swift
//  LicensePlateApp
//
//  Builds `DiscoveryResolution` from gameplay sync outcomes and applies XP ledger reconciliation.
//

import Foundation

@MainActor
enum GameplayXpSyncSupport {

    /// After server accepts a `region_found`, finalize ledger net vs canonical outcome.
    static func applyResolutionForAcceptedGameplayEvent(_ event: TripActivityEvent, sessionId: UUID) {
        guard event.kind == .regionFound else { return }
        guard let payload = event.payload,
              let gidStr = payload[TripActivityEventPayloadKey.gameInstanceId],
              let gameInstanceId = UUID(uuidString: gidStr),
              let regionId = payload[TripActivityEventPayloadKey.regionId], !regionId.isEmpty
        else { return }

        let actor = payload[TripActivityEventPayloadKey.participantId] ?? event.actorId ?? ""
        guard !actor.isEmpty else { return }

        guard let game = try? GameInstanceRepository.shared.instance(byId: gameInstanceId),
              let trip = try? TripSessionRepository.shared.session(byId: sessionId) else { return }

        let mode = game.commonConfig.gameMode
        let tripMode = trip.mode

        let discoveryOutcome: DiscoveryResolutionOutcome = switch mode {
        case .competitive: .acceptedFirst
        case .collaborative: .acceptedShared
        }

        let resolution = discoveryResolution(
            sourceEventId: event.id,
            sessionId: sessionId,
            gameInstanceId: gameInstanceId,
            itemId: regionId,
            actorUserId: actor,
            discoveryOutcome: discoveryOutcome,
            gameMode: mode,
            tripMode: tripMode
        )

        do {
            try XpReconciliationService.shared.consumeResolution(resolution, gameMode: mode, tripMode: tripMode)
        } catch {
            AnalyticsService.shared.log(
                .persistenceSaveFailed(context: "xp_sync_accepted_region_found", error: error.localizedDescription)
            )
        }
    }

    /// Competitive supersede: late find removed; apply canonical resolution for the superseded finder.
    static func applyResolutionForSupersededRegionFound(
        sessionId: UUID,
        supersededLocalId: String,
        uploadedRegionFound: TripActivityEvent,
        rejection: TripActivityEvent
    ) {
        guard uploadedRegionFound.kind == .regionFound else { return }
        guard let p = uploadedRegionFound.payload,
              let gidStr = p[TripActivityEventPayloadKey.gameInstanceId],
              let gameInstanceId = UUID(uuidString: gidStr),
              let regionId = p[TripActivityEventPayloadKey.regionId], !regionId.isEmpty
        else { return }

        let actor = p[TripActivityEventPayloadKey.participantId] ?? uploadedRegionFound.actorId ?? ""
        guard !actor.isEmpty else { return }

        guard let reasonRaw = rejection.payload?[TripActivityEventPayloadKey.rejectionReason] else { return }

        let discoveryOutcome: DiscoveryResolutionOutcome
        switch reasonRaw {
        case DiscoveryRejectionReason.serverRejectedLateCompetitive.rawValue,
            DiscoveryRejectionReason.serverRejectedSupersededByEarlierTimestamp.rawValue:
            discoveryOutcome = .acceptedLate
        case DiscoveryRejectionReason.rejectedInvalidParticipant.rawValue:
            discoveryOutcome = .rejectedInvalidState
        default:
            return
        }

        guard let game = try? GameInstanceRepository.shared.instance(byId: gameInstanceId),
              let trip = try? TripSessionRepository.shared.session(byId: sessionId) else { return }

        let mode = game.commonConfig.gameMode
        let tripMode = trip.mode

        let resolution = discoveryResolution(
            sourceEventId: supersededLocalId,
            sessionId: sessionId,
            gameInstanceId: gameInstanceId,
            itemId: regionId,
            actorUserId: actor,
            discoveryOutcome: discoveryOutcome,
            gameMode: mode,
            tripMode: tripMode
        )

        do {
            try XpReconciliationService.shared.consumeResolution(resolution, gameMode: mode, tripMode: tripMode)
        } catch {
            AnalyticsService.shared.log(
                .persistenceSaveFailed(context: "xp_sync_superseded_region_found", error: error.localizedDescription)
            )
        }
    }

    private static func discoveryResolution(
        sourceEventId: String,
        sessionId: UUID,
        gameInstanceId: UUID,
        itemId: String,
        actorUserId: String,
        discoveryOutcome: DiscoveryResolutionOutcome,
        gameMode: GameMode,
        tripMode: TripMode
    ) -> DiscoveryResolution {
        let tripMirror = TripScoringOutcome(rawValue: discoveryOutcome.rawValue) ?? .pending
        let personalMirror = PersonalHistoryOutcome(rawValue: discoveryOutcome.rawValue) ?? .pending
        let resolutionId = "xp_res:v1:\(sourceEventId):\(discoveryOutcome.rawValue)"
        var draft = DiscoveryResolution(
            resolutionId: resolutionId,
            sourceEventId: sourceEventId,
            sessionId: sessionId,
            gameInstanceId: gameInstanceId,
            itemId: itemId,
            actorUserId: actorUserId,
            finalOutcome: discoveryOutcome,
            tripScoringOutcome: tripMirror,
            personalHistoryOutcome: personalMirror,
            finalXpAward: 0,
            xpReason: .discoveryClaimPendingResolution
        )
        let award = XpAwardRuleEngine.compute(from: draft, gameMode: gameMode, tripMode: tripMode)
        return DiscoveryResolution(
            resolutionId: resolutionId,
            sourceEventId: sourceEventId,
            sessionId: sessionId,
            gameInstanceId: gameInstanceId,
            itemId: itemId,
            actorUserId: actorUserId,
            finalOutcome: discoveryOutcome,
            tripScoringOutcome: tripMirror,
            personalHistoryOutcome: personalMirror,
            finalXpAward: award.xpNet,
            xpReason: award.xpReason
        )
    }
}
