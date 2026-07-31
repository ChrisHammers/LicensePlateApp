//
//  XpReconciliationService.swift
//  LicensePlateApp
//
//  Provisional discovery XP for offline UX; final local ledger rows only after cloud confirmation.
//

import Foundation

struct XpClawbackNotice: Equatable, Sendable {
    var regionId: String
    var xpRemoved: Int
    var sourceEventId: String
    var sessionId: UUID
    var gameInstanceId: UUID
}

@MainActor
final class XpReconciliationService {

    static let shared = XpReconciliationService()

    /// Last clawback produced by settlement (consumed by toast / reward presentation).
    private(set) var lastClawbackNotice: XpClawbackNotice?

    private let xpLedger: XpLedgerRepositoryProtocol
    private let resolutionRepo: DiscoveryResolutionRepositoryProtocol
    private let tripActivityEvents: TripActivityEventRepositoryProtocol
    private let gameRepository: GameInstanceRepositoryProtocol
    private let tripSessionRepository: TripSessionRepositoryProtocol
    private let rewardsConfig: ProgressionRewardsConfigProviding
    private let clawbackHandler: ((XpClawbackNotice) -> Void)?

    init(
        xpLedger: XpLedgerRepositoryProtocol = XpLedgerRepository.shared,
        resolutionRepo: DiscoveryResolutionRepositoryProtocol = DiscoveryResolutionRepository.shared,
        tripActivityEvents: TripActivityEventRepositoryProtocol = TripActivityEventRepository.shared,
        gameRepository: GameInstanceRepositoryProtocol = GameInstanceRepository.shared,
        tripSessionRepository: TripSessionRepositoryProtocol = TripSessionRepository.shared,
        rewardsConfig: ProgressionRewardsConfigProviding = ProgressionRewardsConfigProvider.shared,
        clawbackHandler: ((XpClawbackNotice) -> Void)? = nil
    ) {
        self.xpLedger = xpLedger
        self.resolutionRepo = resolutionRepo
        self.tripActivityEvents = tripActivityEvents
        self.gameRepository = gameRepository
        self.tripSessionRepository = tripSessionRepository
        self.rewardsConfig = rewardsConfig
        self.clawbackHandler = clawbackHandler
    }

    func consumeLastClawbackNotice() -> XpClawbackNotice? {
        defer { lastClawbackNotice = nil }
        return lastClawbackNotice
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
        let expectedXp = expectedProvisionalXp(
            tripMode: tripMode,
            gameMode: game.commonConfig.gameMode,
            rewards: rewards
        )
        guard expectedXp > 0 else { return }

        if tripMode != .solo, game.commonConfig.gameMode == .competitive {
            guard let first = forTarget.first, first.id == event.id else { return }
        }

        let reason: XpReasonCode
        if tripMode == .solo {
            reason = .soloNewDiscovery
        } else {
            switch game.commonConfig.gameMode {
            case .competitive: reason = .discoveryClaimPendingResolution
            case .collaborative: reason = .collaborativeSharedFinder
            }
        }

        let provisional = XpLedgerEvent(
            userId: participantId,
            sessionId: event.sessionId,
            gameInstanceId: gameInstanceId,
            sourceEventId: event.id,
            sourceEventType: TripActivityEventKind.regionFound.rawValue,
            itemId: regionId,
            grantKind: .provisionalDiscoveryXp,
            status: .provisional,
            xpDelta: expectedXp,
            reasonCode: reason,
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
    }

    /// Persists resolution, closes provisional rows, and writes a final local mirror only when cloud confirms XP.
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

        if try hasSettledResolution(resolutionId: resolution.resolutionId, baseUniquenessKey: baseKey) {
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
        let resolvedAt = Date()

        let voidedProvisionalXp = try xpLedger.voidProvisionalRows(
            forUniquenessKey: baseKey,
            resolvedAt: resolvedAt
        )

        let activeRows = try xpLedger.ledgerEvents(forUniquenessKey: baseKey)
            .filter { $0.status != .voided }

        if targetNet > 0 {
            let hasFinal = activeRows.contains { $0.grantKind == .finalDiscoveryAward }
            if !hasFinal {
                let finalEvent = XpLedgerEvent(
                    userId: resolution.actorUserId,
                    sessionId: resolution.sessionId,
                    gameInstanceId: resolution.gameInstanceId,
                    sourceEventId: resolution.sourceEventId,
                    sourceEventType: TripActivityEventKind.regionFound.rawValue,
                    itemId: resolution.itemId,
                    grantKind: .finalDiscoveryAward,
                    status: .final,
                    xpDelta: targetNet,
                    reasonCode: award.xpReason,
                    xpUniquenessKey: baseKey,
                    resolvedAt: resolvedAt,
                    metadata: [
                        XpLedgerMetadataKey.resolutionId: resolution.resolutionId,
                        XpLedgerMetadataKey.originalDiscoveryEventId: resolution.sourceEventId,
                    ]
                )
                try xpLedger.append(finalEvent)
            }
        }

        let rowsAfterFinal = try xpLedger.ledgerEvents(forUniquenessKey: baseKey)
            .filter { $0.status != .voided }
        let netAfterFinal = rowsAfterFinal.reduce(0) { $0 + $1.xpDelta }
        let rawDelta = targetNet - netAfterFinal
        // Allow negative clawbacks so rejected finds clear provisional XP.
        let delta = rawDelta
        if delta != 0 {
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
                resolvedAt: resolvedAt,
                metadata: meta
            )
            try xpLedger.append(adjustment)
        } else if targetNet == 0 {
            // Idempotency marker when clawback only voided provisional rows.
            let marker = XpLedgerEvent(
                userId: resolution.actorUserId,
                sessionId: resolution.sessionId,
                gameInstanceId: resolution.gameInstanceId,
                sourceEventId: resolution.resolutionId,
                sourceEventType: "discovery_resolution",
                itemId: resolution.itemId,
                grantKind: .reconciliationAdjustment,
                status: .final,
                xpDelta: 0,
                reasonCode: award.xpReason,
                xpUniquenessKey: baseKey,
                resolvedAt: resolvedAt,
                metadata: [
                    XpLedgerMetadataKey.resolutionId: resolution.resolutionId,
                    XpLedgerMetadataKey.originalDiscoveryEventId: resolution.sourceEventId,
                ]
            )
            try xpLedger.append(marker)
        }

        if targetNet == 0, voidedProvisionalXp > 0 {
            let notice = XpClawbackNotice(
                regionId: resolution.itemId,
                xpRemoved: voidedProvisionalXp,
                sourceEventId: resolution.sourceEventId,
                sessionId: resolution.sessionId,
                gameInstanceId: resolution.gameInstanceId
            )
            lastClawbackNotice = notice
            clawbackHandler?(notice)
            XpClawbackPresentationService.shared.enqueue(notice)
        }
    }

    private func expectedProvisionalXp(
        tripMode: TripMode?,
        gameMode: GameMode,
        rewards: ProgressionRewardsConfig
    ) -> Int {
        // Always provisional base discovery XP. First-finder +5 is added only after cloud confirms acceptedFirst.
        _ = tripMode
        _ = gameMode
        return rewards.xp.baseDiscoveryXp
    }

    private func hasSettledResolution(resolutionId: String, baseUniquenessKey: String) throws -> Bool {
        let rows = try xpLedger.ledgerEvents(forUniquenessKey: baseUniquenessKey)
        return rows.contains { row in
            row.metadata?[XpLedgerMetadataKey.resolutionId] == resolutionId
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
