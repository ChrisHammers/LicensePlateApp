//
//  XpProgressionDebugExporter.swift
//  LicensePlateApp
//
//  DEBUG — JSON snapshot of server progression, activity/achievement XP grants, and local ledger.
//

import Foundation

#if DEBUG

enum XpProgressionDebugExporter {

    struct SessionContext: Sendable, Equatable {
        var sessionId: UUID
        var gameInstanceId: UUID
        var sessionProgressionPending: ProgressionPendingDelta
        var sessionLedgerNetXp: Int
        var gameLedgerNetXp: Int
    }

    struct Payload: Codable, Sendable {
        struct DisplayedXp: Codable, Sendable {
            var serverTotal: Int
            var verifiedServerTotal: Int?
            var isXpGrantLedgerVerified: Bool
            var ledgerProvisionalPending: Int
            var profileDisplayedTotal: Int
            var effectiveTotal: Int?
            var effectivePendingDelta: Int?
        }

        struct ServerProgression: Codable, Sendable {
            var totalXp: Int
            var acceptedRegionFindCount: Int
            var competitiveFirstPlaceFinishes: Int
            var everCompetitiveFirstPlace: Bool
            var lastUpdatedAt: String?
            var appliedProgressionEventIds: [String]
            var appliedProgressionScopeKeys: [String]
        }

        struct EffectiveTotals: Codable, Sendable {
            var totalXp: Int
            var acceptedRegionFindCount: Int
            var competitiveFirstPlaceFinishes: Int
            var everCompetitiveFirstPlace: Bool
            var hasPendingLocalProgression: Bool
        }

        struct SessionContextPayload: Codable, Sendable {
            var sessionId: String
            var gameInstanceId: String
            var sessionProgressionPending: PendingDeltaPayload
            var sessionLedgerNetXp: Int
            var gameLedgerNetXp: Int
        }

        struct PendingDeltaPayload: Codable, Sendable {
            var totalXp: Int
            var acceptedRegionFindCount: Int
            var competitiveFirstPlaceFinishes: Int
            var everCompetitiveFirstPlace: Bool
        }

        struct ConfiguredXpSource: Codable, Sendable {
            var id: String
            var xpAmount: Int
            var isWiredToGrant: Bool
            var grantPath: String?
        }

        struct AchievementXpGrant: Codable, Sendable {
            var achievementId: String
            var titleKey: String
            var catalogXpReward: Int
            var storedXpReward: Int?
            var xpRewardUsedForReconstruction: Int
            var unlockedAt: String?
            var lastProgress: Int
            var xpScopeAppliedOnServer: Bool
            var source: String
        }

        struct ServerXpGrant: Codable, Sendable {
            var grantId: String
            var amount: Int
            var reason: String
            var sourceType: String
            var sourceId: String
            var idempotencyKey: String
            var sessionId: String?
            var achievementId: String?
            var xpRewardAtGrant: Int?
            var grantedAt: String?
        }

        struct ServerGrantReconciliation: Codable, Sendable {
            var grantCount: Int
            var verifiedTotalXp: Int
            var serverTotalXp: Int
            var totalXpMatchesGrants: Bool
            var unexplainedDeltaAfterGrants: Int
        }

        struct ActivityXpGrant: Codable, Sendable {
            var eventId: String
            var kind: String
            var sessionId: String
            var gameInstanceId: String?
            var regionId: String?
            var xpDelta: Int
            var reason: String
            var appliedOnServer: Bool
            var timestamp: String?
        }

        struct ActivityXpBreakdown: Codable, Sendable {
            var appliedGrants: [ActivityXpGrant]
            var pendingGrants: [ActivityXpGrant]
            var appliedXpTotal: Int
            var pendingXpTotal: Int
            var appliedRegionFindCount: Int
            var appliedCompetitiveWinCount: Int
        }

        struct ServerXpReconciliation: Codable, Sendable {
            var serverTotalXp: Int
            var reconstructedActivityXp: Int
            var reconstructedAchievementXp: Int
            var reconstructedTotal: Int
            var unexplainedDelta: Int
            var note: String
        }

        struct LedgerSummary: Codable, Sendable {
            var eventCount: Int
            var netXpAllRows: Int
            var provisionalSum: Int
            var finalStatusSum: Int
            var netXpByReasonCode: [String: Int]
            var netXpByGrantKind: [String: Int]
        }

        struct LedgerRow: Codable, Sendable {
            var id: String
            var sessionId: String
            var gameInstanceId: String
            var sourceEventId: String
            var sourceEventType: String
            var itemId: String
            var grantKind: String
            var status: String
            var xpDelta: Int
            var reasonCode: String
            var xpUniquenessKey: String
            var createdAt: String
            var resolvedAt: String?
            var metadata: [String: String]?
        }

        var exportedAt: String
        var userId: String
        var displayedXp: DisplayedXp
        var serverProgression: ServerProgression?
        var effectiveTotals: EffectiveTotals?
        var sessionContext: SessionContextPayload?
        var configuredXpSources: [ConfiguredXpSource]
        var achievementXpGrants: [AchievementXpGrant]
        var serverXpGrants: [ServerXpGrant]
        var serverGrantReconciliation: ServerGrantReconciliation
        var activityXpBreakdown: ActivityXpBreakdown
        var serverXpReconciliation: ServerXpReconciliation
        var ledgerSummary: LedgerSummary
        var ledgerEvents: [LedgerRow]
    }

    @MainActor
    static func buildPayload(
        userId: String,
        sessionContext: SessionContext? = nil,
        catalogProvider: ProgressionCatalogProviding = ProgressionCatalogProvider.shared,
        rewards: ProgressionRewardsConfig = ProgressionRewardsConfigProvider.shared.current
    ) throws -> Payload {
        guard !userId.isEmpty else {
            throw ExportError.missingUserId
        }

        let server = UserProgressionRepository.shared.snapshot
        let effective = UserProgressionService.shared.effectiveTotals
        let allLedger = (try? XpLedgerRepository.shared.ledgerEvents(userId: userId)) ?? []
        let provisionalPending = LedgerPendingXpTotals.fromLedgerEvents(allLedger).provisionalSum
        let serverTotal = server?.totalXp ?? 0
        let serverForDelta = server ?? UserProgressionSnapshot.empty
        let effectivePendingDelta = effective.map { $0.totalXp - serverForDelta.totalXp }
        let appliedScopeKeys = server?.appliedProgressionScopeKeys ?? []

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let achievementGrants = buildAchievementXpGrants(
            userId: userId,
            appliedScopeKeys: appliedScopeKeys,
            catalog: catalogProvider.current,
            iso: iso
        )
        let activityBreakdown = buildActivityXpBreakdown(
            userId: userId,
            appliedEventIds: server?.appliedProgressionEventIds ?? [],
            rewards: rewards,
            iso: iso
        )
        let serverGrants = buildServerXpGrants(iso: iso)
        let verifiedServerTotal = serverGrants.reduce(0) { $0 + $1.amount }
        let achievementXpTotal = achievementGrants.reduce(0) { $0 + $1.xpRewardUsedForReconstruction }
        let reconstructed = activityBreakdown.appliedXpTotal + achievementXpTotal
        let grantVerified = verifiedServerTotal == serverTotal

        return Payload(
            exportedAt: iso.string(from: Date()),
            userId: userId,
            displayedXp: Payload.DisplayedXp(
                serverTotal: serverTotal,
                verifiedServerTotal: verifiedServerTotal > 0 || serverTotal == 0 ? verifiedServerTotal : nil,
                isXpGrantLedgerVerified: grantVerified,
                ledgerProvisionalPending: provisionalPending,
                profileDisplayedTotal: (verifiedServerTotal > 0 || serverTotal == 0 ? verifiedServerTotal : serverTotal) + provisionalPending,
                effectiveTotal: effective?.totalXp,
                effectivePendingDelta: effectivePendingDelta
            ),
            serverProgression: server.map {
                Payload.ServerProgression(
                    totalXp: $0.totalXp,
                    acceptedRegionFindCount: $0.acceptedRegionFindCount,
                    competitiveFirstPlaceFinishes: $0.competitiveFirstPlaceFinishes,
                    everCompetitiveFirstPlace: $0.everCompetitiveFirstPlace,
                    lastUpdatedAt: $0.lastUpdatedAt.map { iso.string(from: $0) },
                    appliedProgressionEventIds: $0.appliedProgressionEventIds.sorted(),
                    appliedProgressionScopeKeys: $0.appliedProgressionScopeKeys.sorted()
                )
            },
            effectiveTotals: effective.map {
                Payload.EffectiveTotals(
                    totalXp: $0.totalXp,
                    acceptedRegionFindCount: $0.acceptedRegionFindCount,
                    competitiveFirstPlaceFinishes: $0.competitiveFirstPlaceFinishes,
                    everCompetitiveFirstPlace: $0.everCompetitiveFirstPlace,
                    hasPendingLocalProgression: $0.hasPendingLocalProgression
                )
            },
            sessionContext: sessionContext.map { ctx in
                Payload.SessionContextPayload(
                    sessionId: ctx.sessionId.uuidString,
                    gameInstanceId: ctx.gameInstanceId.uuidString,
                    sessionProgressionPending: pendingPayload(ctx.sessionProgressionPending),
                    sessionLedgerNetXp: ctx.sessionLedgerNetXp,
                    gameLedgerNetXp: ctx.gameLedgerNetXp
                )
            },
            configuredXpSources: configuredXpSources(rewards: rewards),
            achievementXpGrants: achievementGrants,
            serverXpGrants: serverGrants,
            serverGrantReconciliation: Payload.ServerGrantReconciliation(
                grantCount: serverGrants.count,
                verifiedTotalXp: verifiedServerTotal,
                serverTotalXp: serverTotal,
                totalXpMatchesGrants: grantVerified,
                unexplainedDeltaAfterGrants: serverTotal - verifiedServerTotal
            ),
            activityXpBreakdown: activityBreakdown,
            serverXpReconciliation: Payload.ServerXpReconciliation(
                serverTotalXp: serverTotal,
                reconstructedActivityXp: activityBreakdown.appliedXpTotal,
                reconstructedAchievementXp: achievementXpTotal,
                reconstructedTotal: reconstructed,
                unexplainedDelta: serverTotal - reconstructed,
                note: grantVerified
                    ? "Server totalXp matches sum of server xp_grants. Reconstruction gap is expected when achievement catalog xpReward differs from stored unlock xpReward or pre-ledger activity XP was sealed into legacy_unledgered_balance."
                    : "Run reconcileXpGrantLedger (auto on sign-in) to backfill achievement grants and seal legacy orphan XP. Reconstruction uses stored achievement xpReward when available, else catalog."
            ),
            ledgerSummary: ledgerSummary(for: allLedger),
            ledgerEvents: allLedger.map { ledgerRow($0, iso: iso) }
        )
    }

    @MainActor
    static func buildJSON(
        userId: String,
        sessionContext: SessionContext? = nil
    ) throws -> String {
        let payload = try buildPayload(userId: userId, sessionContext: sessionContext)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        guard let text = String(data: data, encoding: .utf8) else {
            throw ExportError.encodingFailed
        }
        return text
    }

    @MainActor
    static func resolvedUserId(from authService: FirebaseAuthService) -> String {
        authService.currentUser?.firebaseUID ?? authService.currentUser?.id ?? ""
    }

    @MainActor
    static func resolvedUserIdFromProgressionRepository() -> String {
        UserProgressionRepository.shared.currentObservedUserId ?? ""
    }

    // MARK: - Private

    enum ExportError: LocalizedError {
        case missingUserId
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .missingUserId: return "No signed-in user id for XP export."
            case .encodingFailed: return "Could not encode XP debug JSON."
            }
        }
    }

    private static func pendingPayload(_ pending: ProgressionPendingDelta) -> Payload.PendingDeltaPayload {
        Payload.PendingDeltaPayload(
            totalXp: pending.totalXp,
            acceptedRegionFindCount: pending.acceptedRegionFindCount,
            competitiveFirstPlaceFinishes: pending.competitiveFirstPlaceFinishes,
            everCompetitiveFirstPlace: pending.everCompetitiveFirstPlace
        )
    }

    private static func configuredXpSources(rewards: ProgressionRewardsConfig) -> [Payload.ConfiguredXpSource] {
        let xp = rewards.xp
        return [
            Payload.ConfiguredXpSource(
                id: "baseDiscoveryXp",
                xpAmount: xp.baseDiscoveryXp,
                isWiredToGrant: true,
                grantPath: "Server: trip activity region_found + xp_grants row. Local: XP ledger provisional/final rows."
            ),
            Payload.ConfiguredXpSource(
                id: "firstFinderBonusXp",
                xpAmount: xp.firstFinderBonusXp,
                isWiredToGrant: true,
                grantPath: "Server: competitive accepted region_found includes base+bonus (15). Local: provisional +10, then +5 when confirmed first finder; late keeps +10."
            ),
            Payload.ConfiguredXpSource(
                id: "competitiveFirstPlaceFinishBonusXp",
                xpAmount: xp.competitiveFirstPlaceFinishBonusXp,
                isWiredToGrant: true,
                grantPath: "Server: trip activity game_ended (competitive rank 1)."
            ),
            Payload.ConfiguredXpSource(
                id: "achievementXpReward",
                xpAmount: 0,
                isWiredToGrant: true,
                grantPath: "Server: syncUserAchievementUnlocks → user_progression.totalXp increment + xp_grants row with stored xpReward."
            ),
            Payload.ConfiguredXpSource(
                id: "firstPlateFindBonusXp",
                xpAmount: xp.firstPlateFindBonusXp,
                isWiredToGrant: false,
                grantPath: nil
            ),
            Payload.ConfiguredXpSource(
                id: "baseMultiplayerGameBonusXp",
                xpAmount: xp.baseMultiplayerGameBonusXp,
                isWiredToGrant: false,
                grantPath: nil
            ),
            Payload.ConfiguredXpSource(
                id: "competitiveSecondPlaceFinishBonusXp",
                xpAmount: xp.competitiveSecondPlaceFinishBonusXp,
                isWiredToGrant: false,
                grantPath: nil
            ),
            Payload.ConfiguredXpSource(
                id: "competitiveThirdPlaceFinishBonusXp",
                xpAmount: xp.competitiveThirdPlaceFinishBonusXp,
                isWiredToGrant: false,
                grantPath: nil
            ),
            Payload.ConfiguredXpSource(
                id: "gameContributorBonusXp",
                xpAmount: xp.gameContributorBonusXp,
                isWiredToGrant: false,
                grantPath: nil
            ),
            Payload.ConfiguredXpSource(
                id: "tripContributorBonusXp",
                xpAmount: xp.tripContributorBonusXp,
                isWiredToGrant: false,
                grantPath: nil
            ),
            Payload.ConfiguredXpSource(
                id: "firstTripCompletionBonusXp",
                xpAmount: xp.firstTripCompletionBonusXp,
                isWiredToGrant: false,
                grantPath: nil
            ),
            Payload.ConfiguredXpSource(
                id: "firstMultiplayerTripCompletionBonusXp",
                xpAmount: xp.firstMultiplayerTripCompletionBonusXp,
                isWiredToGrant: false,
                grantPath: nil
            ),
            Payload.ConfiguredXpSource(
                id: "firstGameCompletionBonusXp",
                xpAmount: xp.firstGameCompletionBonusXp,
                isWiredToGrant: false,
                grantPath: nil
            ),
            Payload.ConfiguredXpSource(
                id: "firstMultiplayerGameCompletionBonusXp",
                xpAmount: xp.firstMultiplayerGameCompletionBonusXp,
                isWiredToGrant: false,
                grantPath: nil
            ),
            Payload.ConfiguredXpSource(
                id: "baseMilestoneBonusXp",
                xpAmount: xp.baseMilestoneBonusXp,
                isWiredToGrant: false,
                grantPath: nil
            ),
            Payload.ConfiguredXpSource(
                id: "returnStreakDailyXp",
                xpAmount: 0,
                isWiredToGrant: false,
                grantPath: "Return streak has celebration UI only; no XP grant."
            ),
        ]
    }

    @MainActor
    private static func buildAchievementXpGrants(
        userId: String,
        appliedScopeKeys: Set<String>,
        catalog: ProgressionCatalog,
        iso: ISO8601DateFormatter
    ) -> [Payload.AchievementXpGrant] {
        let local = (try? UserAchievementRepository.shared.fetchRecords(forUserId: userId)) ?? [:]
        let remote = UserAchievementRemoteRepository.shared.records
        let merged = AchievementProgressPersistence.mergedRecords(local: local, remote: remote)
        let catalogById = Dictionary(uniqueKeysWithValues: catalog.achievements.map { ($0.id, $0) })

        return merged.keys.sorted().compactMap { achievementId in
            guard let record = merged[achievementId],
                  let entry = catalogById[achievementId] else { return nil }
            let scopeKey = achievementUnlockScopeKey(userId: userId, achievementId: achievementId)
            let inLocal = local[achievementId] != nil
            let inRemote = remote[achievementId] != nil
            let source: String
            if inLocal && inRemote { source = "local_and_remote" }
            else if inRemote { source = "remote" }
            else { source = "local" }

            return Payload.AchievementXpGrant(
                achievementId: achievementId,
                titleKey: entry.titleKey,
                catalogXpReward: entry.xpReward,
                storedXpReward: record.storedXpReward,
                xpRewardUsedForReconstruction: record.storedXpReward ?? entry.xpReward,
                unlockedAt: iso.string(from: record.unlockedAt),
                lastProgress: record.lastProgress,
                xpScopeAppliedOnServer: appliedScopeKeys.contains(scopeKey),
                source: source
            )
        }
    }

    @MainActor
    private static func buildServerXpGrants(iso: ISO8601DateFormatter) -> [Payload.ServerXpGrant] {
        XpGrantRemoteRepository.shared.grants.map { grant in
            Payload.ServerXpGrant(
                grantId: grant.grantId,
                amount: grant.amount,
                reason: grant.reason,
                sourceType: grant.sourceType,
                sourceId: grant.sourceId,
                idempotencyKey: grant.idempotencyKey,
                sessionId: grant.sessionId,
                achievementId: grant.achievementId,
                xpRewardAtGrant: grant.xpRewardAtGrant,
                grantedAt: grant.grantedAt.map { iso.string(from: $0) }
            )
        }
    }

    @MainActor
    private static func buildActivityXpBreakdown(
        userId: String,
        appliedEventIds: Set<String>,
        rewards: ProgressionRewardsConfig,
        iso: ISO8601DateFormatter
    ) -> Payload.ActivityXpBreakdown {
        let sessionIds = (try? TripActivityEventRepository.shared.sessionIdsRelevantToProgression(forUserId: userId)) ?? []
        var applied: [Payload.ActivityXpGrant] = []
        var pending: [Payload.ActivityXpGrant] = []
        var appliedRegionFinds = 0
        var appliedWins = 0

        for sid in sessionIds {
            guard let trip = try? TripSessionRepository.shared.session(byId: sid) else { continue }
            let roster = trip.participants.filter { $0.leftAt == nil }.map(\.userId)
            guard roster.contains(userId) else { continue }
            guard let events = try? TripActivityEventRepository.shared.events(sessionId: sid, limit: nil) else { continue }
            guard let games = try? GameInstanceRepository.shared.fetchByTripSession(sessionId: sid) else { continue }
            let gamesById = Dictionary(uniqueKeysWithValues: games.map { ($0.id, $0.progressionGameSnapshot) })

            let ordered = events.sorted { $0.timestamp < $1.timestamp }
            let firstFindByKey = earliestFindEventIdByScopedKey(orderedEvents: ordered, subjectUserId: userId)

            for event in ordered {
                switch event.kind {
                case .regionFound:
                    guard var grant = regionFoundGrant(
                        event: event,
                        userId: userId,
                        firstFindByKey: firstFindByKey,
                        baseXp: rewards.xp.baseDiscoveryXp,
                        iso: iso
                    ) else { continue }
                    let isApplied = appliedEventIds.contains(event.id)
                    grant.appliedOnServer = isApplied
                    if isApplied {
                        applied.append(grant)
                        appliedRegionFinds += 1
                    } else {
                        pending.append(grant)
                    }

                case .gameEnded:
                    guard var grant = competitiveWinGrant(
                        event: event,
                        userId: userId,
                        rosterUserIds: roster,
                        orderedEvents: ordered,
                        gamesById: gamesById,
                        winXp: rewards.xp.competitiveFirstPlaceFinishBonusXp,
                        iso: iso
                    ) else { continue }
                    let isApplied = appliedEventIds.contains(event.id)
                    grant.appliedOnServer = isApplied
                    if isApplied {
                        applied.append(grant)
                        appliedWins += 1
                    } else {
                        pending.append(grant)
                    }

                default:
                    break
                }
            }
        }

        return Payload.ActivityXpBreakdown(
            appliedGrants: applied,
            pendingGrants: pending,
            appliedXpTotal: applied.reduce(0) { $0 + $1.xpDelta },
            pendingXpTotal: pending.reduce(0) { $0 + $1.xpDelta },
            appliedRegionFindCount: appliedRegionFinds,
            appliedCompetitiveWinCount: appliedWins
        )
    }

    private static func regionFoundGrant(
        event: TripActivityEvent,
        userId: String,
        firstFindByKey: [String: String],
        baseXp: Int,
        iso: ISO8601DateFormatter
    ) -> Payload.ActivityXpGrant? {
        guard let pid = regionFoundParticipantId(event), pid == userId else { return nil }
        guard let gameId = gameInstanceUUID(from: event) else { return nil }
        guard let regionId = event.payload?[TripActivityEventPayloadKey.regionId], !regionId.isEmpty else { return nil }
        guard let key = baseDiscoveryScopedKey(for: event, participantId: pid) else { return nil }
        guard firstFindByKey[key] == event.id else { return nil }

        return Payload.ActivityXpGrant(
            eventId: event.id,
            kind: event.kind.rawValue,
            sessionId: event.sessionId.uuidString,
            gameInstanceId: gameId.uuidString,
            regionId: regionId,
            xpDelta: baseXp,
            reason: "region_found_base_discovery",
            appliedOnServer: false,
            timestamp: iso.string(from: event.timestamp)
        )
    }

    private static func competitiveWinGrant(
        event: TripActivityEvent,
        userId: String,
        rosterUserIds: [String],
        orderedEvents: [TripActivityEvent],
        gamesById: [UUID: ProgressionGameSnapshot],
        winXp: Int,
        iso: ISO8601DateFormatter
    ) -> Payload.ActivityXpGrant? {
        guard let gameId = gameInstanceUUID(from: event) else { return nil }
        guard let game = gamesById[gameId], game.gameMode == .competitive else { return nil }

        let window = orderedEvents.filter { $0.timestamp <= event.timestamp }
        let discoveries = TripActivityEventDiscoveryReplay.replay(events: window, gameInstanceFilter: gameId).discoveries
        let byTarget = Dictionary(grouping: discoveries, by: \.targetId)
        let credits = DiscoveryRulesEngine.creditsForDiscoveries(
            mode: game.gameMode,
            discoveriesByTarget: byTarget,
            teams: game.teams
        )
        let raw = ParticipantContributionBuilder.contributionSummary(discoveries: discoveries, credits: credits)
        let merged = TripRosterContributionMerge.merge(
            roster: rosterUserIds.map { TripParticipant(userId: $0) },
            contributions: raw
        )
        let ranked = TripParticipantRanking.rankContributions(merged)
        let rankOnes = Set(ranked.filter { $0.rank == 1 }.map(\.contribution.participantId))
        guard rankOnes.contains(userId) else { return nil }

        return Payload.ActivityXpGrant(
            eventId: event.id,
            kind: event.kind.rawValue,
            sessionId: event.sessionId.uuidString,
            gameInstanceId: gameId.uuidString,
            regionId: nil,
            xpDelta: winXp,
            reason: "competitive_first_place_finish",
            appliedOnServer: false,
            timestamp: iso.string(from: event.timestamp)
        )
    }

    private static func regionFoundParticipantId(_ event: TripActivityEvent) -> String? {
        guard event.kind == .regionFound else { return nil }
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

    private static func achievementUnlockScopeKey(userId: String, achievementId: String) -> String {
        "achievement_xp|v1|\(userId)|\(achievementId)"
    }

    private static func ledgerSummary(for events: [XpLedgerEvent]) -> Payload.LedgerSummary {
        let provisional = events.filter { $0.status == .provisional }.reduce(0) { $0 + $1.xpDelta }
        let finalStatus = events.filter { $0.status == .final }.reduce(0) { $0 + $1.xpDelta }
        var byReason: [String: Int] = [:]
        var byGrantKind: [String: Int] = [:]
        for event in events {
            byReason[event.reasonCode.rawValue, default: 0] += event.xpDelta
            byGrantKind[event.grantKind.rawValue, default: 0] += event.xpDelta
        }
        return Payload.LedgerSummary(
            eventCount: events.count,
            netXpAllRows: events.reduce(0) { $0 + $1.xpDelta },
            provisionalSum: provisional,
            finalStatusSum: finalStatus,
            netXpByReasonCode: byReason.sorted { $0.key < $1.key }.reduce(into: [:]) { $0[$1.key] = $1.value },
            netXpByGrantKind: byGrantKind.sorted { $0.key < $1.key }.reduce(into: [:]) { $0[$1.key] = $1.value }
        )
    }

    private static func ledgerRow(_ event: XpLedgerEvent, iso: ISO8601DateFormatter) -> Payload.LedgerRow {
        Payload.LedgerRow(
            id: event.id,
            sessionId: event.sessionId.uuidString,
            gameInstanceId: event.gameInstanceId.uuidString,
            sourceEventId: event.sourceEventId,
            sourceEventType: event.sourceEventType,
            itemId: event.itemId,
            grantKind: event.grantKind.rawValue,
            status: event.status.rawValue,
            xpDelta: event.xpDelta,
            reasonCode: event.reasonCode.rawValue,
            xpUniquenessKey: event.xpUniquenessKey,
            createdAt: iso.string(from: event.createdAt),
            resolvedAt: event.resolvedAt.map { iso.string(from: $0) },
            metadata: event.metadata
        )
    }
}

#endif
