//
//  XpReconciliationService.swift
//  LicensePlateApp
//
//  Provisional/final discovery XP reconciliation (append-only ledger).
//

import Foundation

@MainActor
final class XpReconciliationService {

    static let shared = XpReconciliationService()

    private let xpLedger: XpLedgerRepositoryProtocol
    private let resolutionRepo: DiscoveryResolutionRepositoryProtocol
    private let tripActivityEvents: TripActivityEventRepositoryProtocol
    private let gameRepository: GameInstanceRepositoryProtocol
    private let tripSessionRepository: TripSessionRepositoryProtocol
    private let rewardsConfig: ProgressionRewardsConfigProviding

    init(
        xpLedger: XpLedgerRepositoryProtocol = XpLedgerRepository.shared,
        resolutionRepo: DiscoveryResolutionRepositoryProtocol = DiscoveryResolutionRepository.shared,
        tripActivityEvents: TripActivityEventRepositoryProtocol = TripActivityEventRepository.shared,
        gameRepository: GameInstanceRepositoryProtocol = GameInstanceRepository.shared,
        tripSessionRepository: TripSessionRepositoryProtocol = TripSessionRepository.shared,
        rewardsConfig: ProgressionRewardsConfigProviding = ProgressionRewardsConfigProvider.shared
    ) {
        self.xpLedger = xpLedger
        self.resolutionRepo = resolutionRepo
        self.tripActivityEvents = tripActivityEvents
        self.gameRepository = gameRepository
        self.tripSessionRepository = tripSessionRepository
        self.rewardsConfig = rewardsConfig
    }

    /// Called after a gameplay event is durably inserted (same timing as progression observer).
    func handleCommittedActivityEvent(_ event: TripActivityEvent) {
        do {
            try handleCommittedActivityEventThrowing(event)
        } catch {
            AnalyticsService.shared.log(
                .persistenceSaveFailed(context: "xp_reconciliation_activity_event", error: error.localizedDescription)
            )
        }
    }

    private func handleCommittedActivityEventThrowing(_ event: TripActivityEvent) throws {
        guard event.kind == .regionFound else { return }
        guard let payload = event.payload,
              let regionId = payload[TripActivityEventPayloadKey.regionId], !regionId.isEmpty,
              let gidStr = payload[TripActivityEventPayloadKey.gameInstanceId],
              let gameInstanceId = UUID(uuidString: gidStr)
        else { return }

        let participantId = payload[TripActivityEventPayloadKey.participantId] ?? event.actorId ?? ""
        guard !participantId.isEmpty else { return }

        guard let game = try gameRepository.instance(byId: gameInstanceId) else { return }
        let trip = try tripSessionRepository.session(byId: event.sessionId)
        let tripMode = trip?.mode

        let discoveries = try tripActivityEvents.discoveries(sessionId: event.sessionId, gameInstanceId: gameInstanceId)
        let forTarget = discoveries.filter { $0.targetId == regionId }.sorted(by: GameDiscovery.orderingAscending)

        let key = XpLedgerKeyBuilder.uniquenessKey(
            userId: participantId,
            sessionId: event.sessionId,
            gameInstanceId: gameInstanceId,
            itemId: regionId,
            xpCategory: .baseRegionDiscovery
        ).storageString

        let rewards = rewardsConfig.current
        let baseDiscoveryXp = rewards.xp.baseDiscoveryXp

        if tripMode == .solo {
            let soloFinal = XpLedgerEvent(
                userId: participantId,
                sessionId: event.sessionId,
                gameInstanceId: gameInstanceId,
                sourceEventId: event.id,
                sourceEventType: TripActivityEventKind.regionFound.rawValue,
                itemId: regionId,
                grantKind: .finalDiscoveryAward,
                status: .final,
                xpDelta: baseDiscoveryXp,
                reasonCode: .soloNewDiscovery,
                xpUniquenessKey: key,
                metadata: [XpLedgerMetadataKey.originalDiscoveryEventId: event.id]
            )
            let inserted = try xpLedger.appendBaseDiscoveryIfAbsent(soloFinal)
            logBaseGrantOutcome(
                inserted: inserted,
                sessionId: event.sessionId,
                gameInstanceId: gameInstanceId,
                regionId: regionId,
                participantId: participantId
            )
            return
        }

        switch game.commonConfig.gameMode {
        case .competitive:
            guard let first = forTarget.first, first.id == event.id else { return }
            let provisional = XpLedgerEvent(
                userId: participantId,
                sessionId: event.sessionId,
                gameInstanceId: gameInstanceId,
                sourceEventId: event.id,
                sourceEventType: TripActivityEventKind.regionFound.rawValue,
                itemId: regionId,
                grantKind: .provisionalDiscoveryXp,
                status: .provisional,
                xpDelta: baseDiscoveryXp,
                reasonCode: .discoveryClaimPendingResolution,
                xpUniquenessKey: key,
                metadata: [XpLedgerMetadataKey.originalDiscoveryEventId: event.id]
            )
            let inserted = try xpLedger.appendBaseDiscoveryIfAbsent(provisional)
            logBaseGrantOutcome(
                inserted: inserted,
                sessionId: event.sessionId,
                gameInstanceId: gameInstanceId,
                regionId: regionId,
                participantId: participantId
            )

        case .collaborative:
            let finalEvent = XpLedgerEvent(
                userId: participantId,
                sessionId: event.sessionId,
                gameInstanceId: gameInstanceId,
                sourceEventId: event.id,
                sourceEventType: TripActivityEventKind.regionFound.rawValue,
                itemId: regionId,
                grantKind: .finalDiscoveryAward,
                status: .final,
                xpDelta: baseDiscoveryXp,
                reasonCode: .collaborativeSharedFinder,
                xpUniquenessKey: key,
                metadata: [XpLedgerMetadataKey.originalDiscoveryEventId: event.id]
            )
            let inserted = try xpLedger.appendBaseDiscoveryIfAbsent(finalEvent)
            logBaseGrantOutcome(
                inserted: inserted,
                sessionId: event.sessionId,
                gameInstanceId: gameInstanceId,
                regionId: regionId,
                participantId: participantId
            )
        }
    }

    /// Persists resolution and applies compensating ledger rows so net XP matches the award engine.
    func consumeResolution(
        _ resolution: DiscoveryResolution,
        gameMode: GameMode,
        tripMode: TripMode?
    ) throws {
        guard resolution.finalOutcome != .pending else { return }

        let baseKey = XpLedgerKeyBuilder.uniquenessKey(
            userId: resolution.actorUserId,
            sessionId: resolution.sessionId,
            gameInstanceId: resolution.gameInstanceId,
            itemId: resolution.itemId,
            xpCategory: .baseRegionDiscovery
        ).storageString

        if try hasAdjustmentForResolution(resolutionId: resolution.resolutionId, baseUniquenessKey: baseKey) {
            return
        }

        try resolutionRepo.save(resolution)

        let rewards = rewardsConfig.current
        let award = XpAwardRuleEngine.compute(
            from: resolution,
            gameMode: gameMode,
            tripMode: tripMode,
            rewards: rewards
        )
        let targetNet = award.xpNet

        let rows = try xpLedger.ledgerEvents(forUniquenessKey: baseKey)
        let currentNet = rows.reduce(0) { $0 + $1.xpDelta }
        let rawDelta = targetNet - currentNet
        let delta = max(rewards.policy.minimumLocalReconciliationDelta, rawDelta)
        guard delta != 0 else { return }

        var meta: [String: String] = [XpLedgerMetadataKey.resolutionId: resolution.resolutionId]
        meta[XpLedgerMetadataKey.originalDiscoveryEventId] = resolution.sourceEventId

        let adjustment = XpLedgerEvent(
            userId: resolution.actorUserId,
            sessionId: resolution.sessionId,
            gameInstanceId: resolution.gameInstanceId,
            sourceEventId: resolution.resolutionId,
            sourceEventType: "discovery_resolution",
            itemId: resolution.itemId,
            grantKind: .reconciliationAdjustment,
            status: .final,
            xpDelta: delta,
            reasonCode: award.xpReason,
            xpUniquenessKey: baseKey,
            metadata: meta
        )
        try xpLedger.append(adjustment)
    }

    private func hasAdjustmentForResolution(resolutionId: String, baseUniquenessKey: String) throws -> Bool {
        let rows = try xpLedger.ledgerEvents(forUniquenessKey: baseUniquenessKey)
        return rows.contains { row in
            row.grantKind == .reconciliationAdjustment
                && row.metadata?[XpLedgerMetadataKey.resolutionId] == resolutionId
        }
    }

    private func logBaseGrantOutcome(
        inserted: Bool,
        sessionId: UUID,
        gameInstanceId: UUID,
        regionId: String,
        participantId: String
    ) {
        if inserted {
            AnalyticsService.shared.log(.xpGrantAwarded(
                tripId: sessionId.uuidString,
                gameInstanceId: gameInstanceId.uuidString,
                targetId: regionId,
                participantId: participantId
            ))
        } else {
            AnalyticsService.shared.log(.xpGrantSkippedAlreadyGranted(
                tripId: sessionId.uuidString,
                gameInstanceId: gameInstanceId.uuidString,
                targetId: regionId,
                participantId: participantId
            ))
        }
    }
}
