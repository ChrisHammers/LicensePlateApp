//
//  XpReconciliationService.swift
//  LicensePlateApp
//
//  Provisional discovery XP for offline UX; final local ledger rows only after cloud confirmation.
//

import Foundation

extension Notification.Name {
    /// Posted after `XpReconciliationService.consumeResolution` successfully settles a discovery claim.
    /// `userInfo` keys: `sessionId` (`UUID`), `gameInstanceId` (`UUID`).
    static let discoveryXpResolutionSettled = Notification.Name("XpReconciliationService.discoveryXpResolutionSettled")
}

enum DiscoveryXpResolutionSettledUserInfoKey {
    static let sessionId = "sessionId"
    static let gameInstanceId = "gameInstanceId"
}

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
        switch event.kind {
        case .regionFound:
            break
        case .gameCompleted, .gameEnded, .tripEnded:
            try handleCompletionEventThrowing(event)
            return
        default:
            return
        }
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
        if inserted {
            try appendLocalFindBonusesIfAbsent(
                event: event,
                participantId: participantId,
                gameInstanceId: gameInstanceId,
                regionId: regionId,
                rewards: rewards
            )
        }
        logBaseGrantOutcome(
            inserted: inserted,
            sessionId: event.sessionId,
            gameInstanceId: gameInstanceId,
            regionId: regionId,
            participantId: participantId
        )
    }

    /// Local provisional rows for the two find bonuses that are otherwise server-only:
    /// lifetime-first (new plate) and first-of-day.
    ///
    /// FR-60 makes an unconsented child local-only, and both bonuses are minted server-side from
    /// `appliedProgressionScopes` (`lifetime_unique_region|v1|<uid>|<regionId>` and
    /// `first_find_of_day|v1|<uid>|<dayKey>`), so a child who never reaches the server never earned
    /// them — the owner's parity ruling is that points must not depend on whether consent has
    /// landed, and lifetime uniques are what the collection goals are counted from. FR-28e's rule
    /// is the pattern: every award category gets a local provisional writer, reconciled
    /// idempotently once the server grant lands.
    ///
    /// Reconciliation: both rows carry the find's own `sourceEventId`, so
    /// `LedgerPendingXpTotals.isServerApplied` drops them the moment that event id appears in
    /// `appliedProgressionEvents` — the same mechanism that already retires the base award, and the
    /// reason a late replay cannot pay twice. The keys mirror the server scopes exactly (global
    /// scope, so lifetime-unique is once per region for all time and first-of-day is once per day),
    /// which is what makes a *second* find of the same plate mint nothing locally either.
    ///
    /// Both rows are written under `XpLedgerGlobalScope` — the same account-scoped shape
    /// `ReturnStreakService` uses — because that is what the mirrored server scopes are: neither
    /// bonus is per-session, and a row whose scope columns disagreed with its own key could not be
    /// repaired after an identity rebind.
    ///
    /// Only called when the base award was newly inserted, so the competitive first-writer gate and
    /// the duplicate-find gate above govern the bonuses too.
    private func appendLocalFindBonusesIfAbsent(
        event: TripActivityEvent,
        participantId: String,
        gameInstanceId: UUID,
        regionId: String,
        rewards: ProgressionRewardsConfig
    ) throws {
        let lifetimeUniqueXp = rewards.xp.lifetimeUniqueRegionFindBonusXp
        if lifetimeUniqueXp > 0 {
            _ = try xpLedger.appendIfAbsent(
                bonusRow(
                    event: event,
                    participantId: participantId,
                    itemId: regionId,
                    xpDelta: lifetimeUniqueXp,
                    reasonCode: .lifetimeUniqueRegion,
                    xpUniquenessKey: Self.lifetimeUniqueRegionKey(userId: participantId, regionId: regionId)
                )
            )
        }

        let firstOfDayXp = rewards.xp.firstFindOfDayBonusXp
        guard firstOfDayXp > 0 else { return }
        let dayKey = Self.xpDayKey(for: event)
        _ = try xpLedger.appendIfAbsent(
            bonusRow(
                event: event,
                participantId: participantId,
                itemId: dayKey,
                xpDelta: firstOfDayXp,
                reasonCode: .firstFindOfDay,
                xpUniquenessKey: Self.firstFindOfDayKey(userId: participantId, dayKey: dayKey)
            )
        )
    }

    private func bonusRow(
        event: TripActivityEvent,
        participantId: String,
        itemId: String,
        xpDelta: Int,
        reasonCode: XpReasonCode,
        xpUniquenessKey: String
    ) -> XpLedgerEvent {
        XpLedgerEvent(
            userId: participantId,
            sessionId: XpLedgerGlobalScope.sessionId,
            gameInstanceId: XpLedgerGlobalScope.gameInstanceId,
            sourceEventId: event.id,
            sourceEventType: TripActivityEventKind.regionFound.rawValue,
            itemId: itemId,
            grantKind: .provisionalDiscoveryXp,
            status: .provisional,
            xpDelta: xpDelta,
            reasonCode: reasonCode,
            xpUniquenessKey: xpUniquenessKey,
            metadata: [XpLedgerMetadataKey.originalDiscoveryEventId: event.id]
        )
    }

    /// Mirrors `lifetime_unique_region|v1|<uid>|<regionId>`: no session, no game, so the bonus is
    /// once per region for the life of the account.
    static func lifetimeUniqueRegionKey(userId: String, regionId: String) -> String {
        XpLedgerKeyBuilder.uniquenessKey(
            userId: userId,
            sessionId: XpLedgerGlobalScope.sessionId,
            gameInstanceId: XpLedgerGlobalScope.gameInstanceId,
            itemId: regionId,
            xpCategory: .lifetimeUniqueRegion
        ).storageString
    }

    /// Mirrors `first_find_of_day|v1|<uid>|<dayKey>`: once per user per calendar day.
    static func firstFindOfDayKey(userId: String, dayKey: String) -> String {
        XpLedgerKeyBuilder.uniquenessKey(
            userId: userId,
            sessionId: XpLedgerGlobalScope.sessionId,
            gameInstanceId: XpLedgerGlobalScope.gameInstanceId,
            itemId: dayKey,
            xpCategory: .firstFindOfDay
        ).storageString
    }

    /// The day key the server will bill this find against.
    ///
    /// Same resolution order as `progressionCore.previewProgressionComponentsForActivityEvent`:
    /// the client-stamped `xpDayKey` when it is well-formed, otherwise the **UTC** day of the
    /// event's own timestamp. Reading the event's own day rather than "now" is what carries FR-28h's
    /// rule into the local mirror — a find replayed after consent lands on the historical day scope
    /// and can never read as today's activity.
    static func xpDayKey(for event: TripActivityEvent) -> String {
        if let stamped = event.payload?[TripActivityEventPayloadKey.xpDayKey],
           isWellFormedDayKey(stamped) {
            return stamped
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let parts = calendar.dateComponents([.year, .month, .day], from: event.timestamp)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// `yyyy-MM-dd`, matching the server's `DAY_KEY_RE`.
    private static func isWellFormedDayKey(_ value: String) -> Bool {
        let chars = Array(value)
        guard chars.count == 10, chars[4] == "-", chars[7] == "-" else { return false }
        for index in [0, 1, 2, 3, 5, 6, 8, 9] where !chars[index].isASCII || !chars[index].isNumber {
            return false
        }
        return true
    }

    /// Local provisional rows for completion XP (`game_completed` / `game_ended` / `trip_ended`).
    ///
    /// Without these, completion XP exists only as a pending *total* and never as an itemized ledger row,
    /// so offline play shows find XP but no game/trip bonuses on the profile, rank, toast, or recap.
    /// Amounts come from `ProgressionLocalEngine.completionComponents`, the same mirror of the server's
    /// `awardsForEvent` the pending totals use, so the later server grant reconciles to a no-op: every row
    /// carries `sourceEventId == event.id`, and `LedgerPendingXpTotals` stops counting a row once that id
    /// lands in `appliedProgressionEvents`.
    private func handleCompletionEventThrowing(_ event: TripActivityEvent) throws {
        guard let trip = try tripSessionRepository.session(byId: event.sessionId) else { return }
        guard trip.status != .cancelled else { return }

        let rosterUserIds = trip.participants.filter { $0.leftAt == nil }.map(\.userId)
        guard !rosterUserIds.isEmpty else { return }

        let games = try gameRepository.fetchByTripSession(sessionId: event.sessionId)
        let gamesById = Dictionary(
            games.map { ($0.id, $0.progressionGameSnapshot) },
            uniquingKeysWith: { first, _ in first }
        )

        let components = ProgressionLocalEngine.completionComponents(
            for: event,
            windowIncludingEvent: try sessionWindow(upToAndIncluding: event),
            rosterUserIds: rosterUserIds,
            gamesById: gamesById,
            rewards: rewardsConfig.current
        )

        for component in components where component.amount > 0 {
            let key = XpLedgerKeyBuilder.uniquenessKey(
                userId: component.subjectUserId,
                sessionId: event.sessionId,
                gameInstanceId: component.gameInstanceId ?? XpLedgerGlobalScope.gameInstanceId,
                itemId: component.reason.rawValue,
                xpCategory: .tripCompletion
            ).storageString

            let row = XpLedgerEvent(
                userId: component.subjectUserId,
                sessionId: event.sessionId,
                gameInstanceId: component.gameInstanceId ?? XpLedgerGlobalScope.gameInstanceId,
                sourceEventId: event.id,
                sourceEventType: event.kind.rawValue,
                itemId: component.reason.rawValue,
                grantKind: .tripCompletion,
                status: .provisional,
                xpDelta: component.amount,
                reasonCode: component.reason,
                xpUniquenessKey: key
            )
            _ = try xpLedger.appendIfAbsent(row)
        }
    }

    /// Session events in timestamp order up to and including `event`, matching the replay window
    /// `ProgressionLocalEngine` uses when it reaches the same event.
    private func sessionWindow(upToAndIncluding event: TripActivityEvent) throws -> [TripActivityEvent] {
        let all = try tripActivityEvents.events(sessionId: event.sessionId, limit: nil)
            .sorted { $0.timestamp < $1.timestamp }
        guard let index = all.firstIndex(where: { $0.id == event.id }) else {
            return all + [event]
        }
        return Array(all.prefix(through: index))
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

        var voidedProvisionalXp = try xpLedger.voidProvisionalRows(
            forUniquenessKey: baseKey,
            resolvedAt: resolvedAt
        )
        if targetNet == 0 {
            // A find that resolved to nothing keeps none of its bonuses either — otherwise a
            // duplicate or rejected plate would leave a live local +20/+10 the server will never
            // grant. Scoped to rows this find minted, so an earlier accepted find's first-of-day
            // row is untouched.
            voidedProvisionalXp += try voidLocalFindBonuses(
                sourceEventId: resolution.sourceEventId,
                resolvedAt: resolvedAt
            )
        }

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

        NotificationCenter.default.post(
            name: .discoveryXpResolutionSettled,
            object: nil,
            userInfo: [
                DiscoveryXpResolutionSettledUserInfoKey.sessionId: resolution.sessionId,
                DiscoveryXpResolutionSettledUserInfoKey.gameInstanceId: resolution.gameInstanceId,
            ]
        )
    }

    /// Voids the local lifetime-first / first-of-day rows minted by one find. Returns the XP removed.
    private func voidLocalFindBonuses(sourceEventId: String, resolvedAt: Date) throws -> Int {
        let bonusReasons: Set<XpReasonCode> = [.lifetimeUniqueRegion, .firstFindOfDay]
        let keys = try xpLedger.ledgerEvents(sourceEventId: sourceEventId)
            .filter { $0.status == .provisional && bonusReasons.contains($0.reasonCode) }
            .map(\.xpUniquenessKey)
        var removed = 0
        for key in Set(keys) {
            removed += try xpLedger.voidProvisionalRows(forUniquenessKey: key, resolvedAt: resolvedAt)
        }
        return removed
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
