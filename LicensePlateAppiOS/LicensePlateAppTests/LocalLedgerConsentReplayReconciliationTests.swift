//
//  LocalLedgerConsentReplayReconciliationTests.swift
//  LicensePlateAppTests
//
//  COPPA F-18 / FR-60 local-first child × FR-28e local provisional ledger × FR-28h late replay.
//
//  The sequence these pin is the one owner device testing broke on 2026-08-15: a child plays
//  offline under a device-minted UUID, enters a share code (`LocalPlayIdentityRepository`
//  rebinds every local row onto the new uid), the captain approves, and the held history is
//  late-replayed to the server. Each discovery must end that sequence with EXACTLY ONE award.
//
//  The rebind is simulated here exactly as it behaves today — `XpLedgerEventEntity.userId` is
//  rewritten, `xpUniquenessKey` is NOT — so these tests fail if the ledger ever goes back to
//  trusting the identity frozen inside that derived string.
//

import Foundation
import SwiftData
import Testing
@testable import LicensePlateApp

@MainActor
struct LocalLedgerConsentReplayReconciliationTests {

    /// The device-minted play identity an unconsented child uses (FR-60: no backend account).
    private let localPlayId = "6C6F63-616C-0000-0000-000000000001"
    /// The uid minted at share-code redemption.
    private let consentedUid = "dUGUYEIGswOhIrxrIxM7ZcAeFyp1"

    // MARK: - Harness

    private func makeContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: [config])
        let ctx = ModelContext(container)
        XpLedgerRepository.shared.setModelContext(ctx)
        DiscoveryResolutionRepository.shared.setModelContext(ctx)
        return ctx
    }

    private func makeService(
        events: MockTripActivityEventRepository,
        games: MockGameInstanceRepository,
        trips: MockTripSessionRepository
    ) -> XpReconciliationService {
        XpReconciliationService(
            xpLedger: XpLedgerRepository.shared,
            resolutionRepo: DiscoveryResolutionRepository.shared,
            tripActivityEvents: events,
            gameRepository: games,
            tripSessionRepository: trips,
            clawbackHandler: { _ in }
        )
    }

    /// A solo trip running a collaborative game — what a child playing alone actually has, and the
    /// combination that produced the "+10 collab AND +10 solo for one find" ledger.
    private func seedSoloCollaborativeTrip(
        sessionId: UUID,
        gameId: UUID,
        participantId: String,
        games: MockGameInstanceRepository,
        trips: MockTripSessionRepository
    ) {
        trips.seed(
            TripSession(
                id: sessionId,
                name: "Local play",
                participants: [TripParticipant(userId: participantId, role: .owner, joinedAt: Date())]
            )
        )
        games.seed(
            GameInstance(
                id: gameId,
                definitionId: GameType.licensePlate.rawValue,
                sessionId: sessionId,
                ruleSet: GameRuleSet(gameDefinitionId: "license_plate"),
                commonConfig: CommonGameConfig(
                    lifecycleState: .started,
                    gameMode: .collaborative,
                    configLocked: true,
                    configLockReason: .gameStarted
                )
            )
        )
    }

    private func regionFoundEvent(
        id: String,
        sessionId: UUID,
        gameId: UUID,
        regionId: String,
        participantId: String,
        dayKey: String?,
        timestamp: Date = Date()
    ) -> TripActivityEvent {
        var payload: [String: String] = [
            TripActivityEventPayloadKey.regionId: regionId,
            TripActivityEventPayloadKey.gameInstanceId: gameId.uuidString,
            TripActivityEventPayloadKey.participantId: participantId,
            TripActivityEventPayloadKey.inputMethod: FoundRegion.InputMethod.list.rawValue,
        ]
        if let dayKey {
            payload[TripActivityEventPayloadKey.xpDayKey] = dayKey
        }
        return TripActivityEvent(
            id: id,
            sessionId: sessionId,
            kind: .regionFound,
            timestamp: timestamp,
            actorId: participantId,
            payload: payload
        )
    }

    /// Replays `LocalPlayIdentityRepository.rebindLocalPlayIdentity` faithfully: trip roster,
    /// activity-event `actorId`/payload, and `XpLedgerEventEntity.userId` — and, as today,
    /// **not** the derived `xpUniquenessKey`.
    private func simulateIdentityRebind(
        context: ModelContext,
        sessionId: UUID,
        gameId: UUID,
        events: MockTripActivityEventRepository,
        trips: MockTripSessionRepository,
        games: MockGameInstanceRepository
    ) throws {
        for row in try context.fetch(FetchDescriptor<XpLedgerEventEntity>()) where row.userId == localPlayId {
            row.userId = consentedUid
        }
        try context.save()

        seedSoloCollaborativeTrip(
            sessionId: sessionId,
            gameId: gameId,
            participantId: consentedUid,
            games: games,
            trips: trips
        )

        for event in try events.events(sessionId: sessionId, limit: nil) {
            var payload = event.payload ?? [:]
            for (key, value) in payload where value == localPlayId {
                payload[key] = consentedUid
            }
            try events.reconcileRemoteActivityEvent(
                TripActivityEvent(
                    id: event.id,
                    sessionId: event.sessionId,
                    kind: event.kind,
                    timestamp: event.timestamp,
                    actorId: event.actorId == localPlayId ? consentedUid : event.actorId,
                    payload: payload
                )
            )
        }
    }

    /// What `GameplayXpSyncSupport.applyResolutionForAcceptedGameplayEvent` builds when the server
    /// accepts a replayed find in a collaborative game.
    private func acceptedShareResolution(
        sourceEventId: String,
        sessionId: UUID,
        gameId: UUID,
        regionId: String,
        actorUserId: String
    ) -> DiscoveryResolution {
        DiscoveryResolution(
            resolutionId: "xp_res:v1:\(sourceEventId):\(DiscoveryResolutionOutcome.acceptedShared.rawValue)",
            sourceEventId: sourceEventId,
            sessionId: sessionId,
            gameInstanceId: gameId,
            itemId: regionId,
            actorUserId: actorUserId,
            finalOutcome: .acceptedShared,
            tripScoringOutcome: .acceptedShared,
            personalHistoryOutcome: .acceptedShared,
            finalXpAward: 0,
            xpReason: .discoveryClaimPendingResolution
        )
    }

    private func liveRows(forUserId userId: String) throws -> [XpLedgerEvent] {
        try XpLedgerRepository.shared.ledgerEvents(userId: userId).filter { $0.status != .voided }
    }

    private func baseDiscoveryRows(
        userId: String,
        sessionId: UUID,
        gameId: UUID,
        regionId: String
    ) throws -> [XpLedgerEvent] {
        try liveRows(forUserId: userId).filter {
            $0.sessionId == sessionId
                && $0.gameInstanceId == gameId
                && $0.itemId == regionId
                && ($0.grantKind == .provisionalDiscoveryXp || $0.grantKind == .finalDiscoveryAward)
        }
    }

    // MARK: - Bug A: local play → rebind → late replay → reconcile is single-count

    @Test func localPlayRebindThenLateReplaySettlesToExactlyOneAward() throws {
        let ctx = try makeContext()
        let sessionId = UUID()
        let gameId = UUID()
        let events = MockTripActivityEventRepository()
        let games = MockGameInstanceRepository()
        let trips = MockTripSessionRepository()
        seedSoloCollaborativeTrip(
            sessionId: sessionId,
            gameId: gameId,
            participantId: localPlayId,
            games: games,
            trips: trips
        )

        // 1. Offline local play, no backend identity.
        let find = regionFoundEvent(
            id: "find-CA",
            sessionId: sessionId,
            gameId: gameId,
            regionId: "CA",
            participantId: localPlayId,
            dayKey: "2026-08-10"
        )
        try events.append(find)
        makeService(events: events, games: games, trips: trips).handleCommittedActivityEvent(find)

        // 2. Share-code redemption rebinds every local row onto the new uid.
        try simulateIdentityRebind(
            context: ctx,
            sessionId: sessionId,
            gameId: gameId,
            events: events,
            trips: trips,
            games: games
        )

        // 3. Approval + FR-28h late replay: the server accepts the held find.
        let svc = makeService(events: events, games: games, trips: trips)
        try svc.consumeResolution(
            acceptedShareResolution(
                sourceEventId: "find-CA",
                sessionId: sessionId,
                gameId: gameId,
                regionId: "CA",
                actorUserId: consentedUid
            ),
            gameMode: .collaborative,
            tripMode: .solo
        )

        let base = try baseDiscoveryRows(userId: consentedUid, sessionId: sessionId, gameId: gameId, regionId: "CA")
        #expect(base.count == 1)
        #expect(base.reduce(0) { $0 + $1.xpDelta } == GameProgressionXPRewards.baseDiscoveryXp)
        // Nothing may be left stranded under the retired identity either.
        #expect(try liveRows(forUserId: localPlayId).isEmpty)
    }

    @Test func lateReplayIsIdempotentAcrossRepeatedAccepts() throws {
        let ctx = try makeContext()
        let sessionId = UUID()
        let gameId = UUID()
        let events = MockTripActivityEventRepository()
        let games = MockGameInstanceRepository()
        let trips = MockTripSessionRepository()
        seedSoloCollaborativeTrip(
            sessionId: sessionId,
            gameId: gameId,
            participantId: localPlayId,
            games: games,
            trips: trips
        )

        let find = regionFoundEvent(
            id: "find-NY",
            sessionId: sessionId,
            gameId: gameId,
            regionId: "NY",
            participantId: localPlayId,
            dayKey: "2026-08-10"
        )
        try events.append(find)
        makeService(events: events, games: games, trips: trips).handleCommittedActivityEvent(find)
        try simulateIdentityRebind(
            context: ctx,
            sessionId: sessionId,
            gameId: gameId,
            events: events,
            trips: trips,
            games: games
        )

        let svc = makeService(events: events, games: games, trips: trips)
        let resolution = acceptedShareResolution(
            sourceEventId: "find-NY",
            sessionId: sessionId,
            gameId: gameId,
            regionId: "NY",
            actorUserId: consentedUid
        )
        try svc.consumeResolution(resolution, gameMode: .collaborative, tripMode: .solo)
        try svc.consumeResolution(resolution, gameMode: .collaborative, tripMode: .solo)

        let base = try baseDiscoveryRows(userId: consentedUid, sessionId: sessionId, gameId: gameId, regionId: "NY")
        #expect(base.count == 1)
        #expect(base.reduce(0) { $0 + $1.xpDelta } == GameProgressionXPRewards.baseDiscoveryXp)
    }

    /// The whole-history shape the owner saw: ten zones replayed at once must total ten base awards.
    @Test func tenZoneLocalHistorySurvivesConsentWithoutInflation() throws {
        let ctx = try makeContext()
        let sessionId = UUID()
        let gameId = UUID()
        let events = MockTripActivityEventRepository()
        let games = MockGameInstanceRepository()
        let trips = MockTripSessionRepository()
        seedSoloCollaborativeTrip(
            sessionId: sessionId,
            gameId: gameId,
            participantId: localPlayId,
            games: games,
            trips: trips
        )

        let regions = ["CA", "NY", "TX", "FL", "WA", "OR", "NV", "AZ", "UT", "CO"]
        let svcLocal = makeService(events: events, games: games, trips: trips)
        for (index, region) in regions.enumerated() {
            let find = regionFoundEvent(
                id: "find-\(region)",
                sessionId: sessionId,
                gameId: gameId,
                regionId: region,
                participantId: localPlayId,
                dayKey: "2026-08-10",
                timestamp: Date().addingTimeInterval(Double(index))
            )
            try events.append(find)
            svcLocal.handleCommittedActivityEvent(find)
        }

        try simulateIdentityRebind(
            context: ctx,
            sessionId: sessionId,
            gameId: gameId,
            events: events,
            trips: trips,
            games: games
        )

        let svc = makeService(events: events, games: games, trips: trips)
        for region in regions {
            try svc.consumeResolution(
                acceptedShareResolution(
                    sourceEventId: "find-\(region)",
                    sessionId: sessionId,
                    gameId: gameId,
                    regionId: region,
                    actorUserId: consentedUid
                ),
                gameMode: .collaborative,
                tripMode: .solo
            )
        }

        for region in regions {
            let base = try baseDiscoveryRows(
                userId: consentedUid,
                sessionId: sessionId,
                gameId: gameId,
                regionId: region
            )
            #expect(base.count == 1, "\(region) should hold exactly one base award")
        }

        // Ten finds: ten base awards, ten lifetime-first bonuses, one first-of-day bonus.
        let live = try liveRows(forUserId: consentedUid)
        let baseXp = live.filter { $0.reasonCode != .lifetimeUniqueRegion && $0.reasonCode != .firstFindOfDay }
            .reduce(0) { $0 + $1.xpDelta }
        #expect(baseXp == 10 * GameProgressionXPRewards.baseDiscoveryXp)
        #expect(live.filter { $0.reasonCode == .lifetimeUniqueRegion }.count == 10)
        #expect(live.filter { $0.reasonCode == .firstFindOfDay }.count == 1)
    }

    /// Once the server reports the find's event id applied, every local row it minted drops out of
    /// the pending projection — the single-count guarantee end to end.
    @Test func serverAppliedEventRetiresBaseAndBonusRows() throws {
        _ = try makeContext()
        let sessionId = UUID()
        let gameId = UUID()
        let events = MockTripActivityEventRepository()
        let games = MockGameInstanceRepository()
        let trips = MockTripSessionRepository()
        seedSoloCollaborativeTrip(
            sessionId: sessionId,
            gameId: gameId,
            participantId: consentedUid,
            games: games,
            trips: trips
        )

        let find = regionFoundEvent(
            id: "find-ME",
            sessionId: sessionId,
            gameId: gameId,
            regionId: "ME",
            participantId: consentedUid,
            dayKey: "2026-08-10"
        )
        try events.append(find)
        makeService(events: events, games: games, trips: trips).handleCommittedActivityEvent(find)

        let rows = try XpLedgerRepository.shared.ledgerEvents(userId: consentedUid)
        let beforeApply = LedgerPendingXpTotals.openProvisionalSum(from: rows, appliedProgressionEventIds: [])
        #expect(beforeApply == GameProgressionXPRewards.baseDiscoveryXp
            + GameProgressionXPRewards.lifetimeUniqueRegionFindBonusXp
            + GameProgressionXPRewards.firstFindOfDayBonusXp)

        let afterApply = LedgerPendingXpTotals.openProvisionalSum(
            from: rows,
            appliedProgressionEventIds: ["find-ME"]
        )
        #expect(afterApply == 0)
    }

    // MARK: - Bug D: ledger shape

    @Test func oneDiscoveryNeverHoldsBothCollabAndSoloAwards() throws {
        let ctx = try makeContext()
        let sessionId = UUID()
        let gameId = UUID()
        let events = MockTripActivityEventRepository()
        let games = MockGameInstanceRepository()
        let trips = MockTripSessionRepository()
        seedSoloCollaborativeTrip(
            sessionId: sessionId,
            gameId: gameId,
            participantId: localPlayId,
            games: games,
            trips: trips
        )

        let find = regionFoundEvent(
            id: "find-VT",
            sessionId: sessionId,
            gameId: gameId,
            regionId: "VT",
            participantId: localPlayId,
            dayKey: "2026-08-10"
        )
        try events.append(find)
        makeService(events: events, games: games, trips: trips).handleCommittedActivityEvent(find)
        try simulateIdentityRebind(
            context: ctx,
            sessionId: sessionId,
            gameId: gameId,
            events: events,
            trips: trips,
            games: games
        )
        try makeService(events: events, games: games, trips: trips).consumeResolution(
            acceptedShareResolution(
                sourceEventId: "find-VT",
                sessionId: sessionId,
                gameId: gameId,
                regionId: "VT",
                actorUserId: consentedUid
            ),
            gameMode: .collaborative,
            tripMode: .solo
        )

        let reasons = Set(
            try baseDiscoveryRows(userId: consentedUid, sessionId: sessionId, gameId: gameId, regionId: "VT")
                .map(\.reasonCode)
        )
        #expect(!reasons.contains(.collaborativeSharedFinder) || !reasons.contains(.soloNewDiscovery))
        #expect(reasons == [.soloNewDiscovery])
    }

    @Test func adultOnlineFindMintsBaseAndBothBonusRowsExactlyOnce() throws {
        _ = try makeContext()
        let sessionId = UUID()
        let gameId = UUID()
        let events = MockTripActivityEventRepository()
        let games = MockGameInstanceRepository()
        let trips = MockTripSessionRepository()
        seedSoloCollaborativeTrip(
            sessionId: sessionId,
            gameId: gameId,
            participantId: consentedUid,
            games: games,
            trips: trips
        )

        let find = regionFoundEvent(
            id: "find-MT",
            sessionId: sessionId,
            gameId: gameId,
            regionId: "MT",
            participantId: consentedUid,
            dayKey: "2026-08-10"
        )
        try events.append(find)
        makeService(events: events, games: games, trips: trips).handleCommittedActivityEvent(find)

        let live = try liveRows(forUserId: consentedUid)
        #expect(live.filter { $0.reasonCode == .lifetimeUniqueRegion }.count == 1)
        #expect(live.filter { $0.reasonCode == .firstFindOfDay }.count == 1)
        #expect(try baseDiscoveryRows(
            userId: consentedUid,
            sessionId: sessionId,
            gameId: gameId,
            regionId: "MT"
        ).count == 1)
    }

    // MARK: - Bug B: local-first children earn the two server-only find bonuses

    @Test func localChildEarnsLifetimeFirstAndFirstOfDayWithoutAnyServer() throws {
        _ = try makeContext()
        let sessionId = UUID()
        let gameId = UUID()
        let events = MockTripActivityEventRepository()
        let games = MockGameInstanceRepository()
        let trips = MockTripSessionRepository()
        seedSoloCollaborativeTrip(
            sessionId: sessionId,
            gameId: gameId,
            participantId: localPlayId,
            games: games,
            trips: trips
        )

        let find = regionFoundEvent(
            id: "find-1",
            sessionId: sessionId,
            gameId: gameId,
            regionId: "CA",
            participantId: localPlayId,
            dayKey: "2026-08-10"
        )
        try events.append(find)
        makeService(events: events, games: games, trips: trips).handleCommittedActivityEvent(find)

        let live = try liveRows(forUserId: localPlayId)
        let lifetime = live.filter { $0.reasonCode == .lifetimeUniqueRegion }
        let firstOfDay = live.filter { $0.reasonCode == .firstFindOfDay }
        #expect(lifetime.count == 1)
        #expect(lifetime.first?.xpDelta == GameProgressionXPRewards.lifetimeUniqueRegionFindBonusXp)
        #expect(firstOfDay.count == 1)
        #expect(firstOfDay.first?.xpDelta == GameProgressionXPRewards.firstFindOfDayBonusXp)
        #expect(firstOfDay.first?.itemId == "2026-08-10")
    }

    @Test func lifetimeFirstMintsOncePerRegionAndFirstOfDayOncePerDay() throws {
        _ = try makeContext()
        let gameId = UUID()
        let firstSession = UUID()
        let secondSession = UUID()
        let events = MockTripActivityEventRepository()
        let games = MockGameInstanceRepository()
        let trips = MockTripSessionRepository()

        seedSoloCollaborativeTrip(
            sessionId: firstSession,
            gameId: gameId,
            participantId: localPlayId,
            games: games,
            trips: trips
        )
        let day1First = regionFoundEvent(
            id: "d1-CA",
            sessionId: firstSession,
            gameId: gameId,
            regionId: "CA",
            participantId: localPlayId,
            dayKey: "2026-08-10"
        )
        let day1Second = regionFoundEvent(
            id: "d1-NY",
            sessionId: firstSession,
            gameId: gameId,
            regionId: "NY",
            participantId: localPlayId,
            dayKey: "2026-08-10",
            timestamp: Date().addingTimeInterval(1)
        )
        try events.append(day1First)
        try events.append(day1Second)
        let svc = makeService(events: events, games: games, trips: trips)
        svc.handleCommittedActivityEvent(day1First)
        svc.handleCommittedActivityEvent(day1Second)

        // A later trip on a later day re-finds CA: no second lifetime-first, but a new day bonus.
        let secondGameId = UUID()
        seedSoloCollaborativeTrip(
            sessionId: secondSession,
            gameId: secondGameId,
            participantId: localPlayId,
            games: games,
            trips: trips
        )
        let day2 = regionFoundEvent(
            id: "d2-CA",
            sessionId: secondSession,
            gameId: secondGameId,
            regionId: "CA",
            participantId: localPlayId,
            dayKey: "2026-08-11",
            timestamp: Date().addingTimeInterval(2)
        )
        try events.append(day2)
        makeService(events: events, games: games, trips: trips).handleCommittedActivityEvent(day2)

        let live = try liveRows(forUserId: localPlayId)
        #expect(live.filter { $0.reasonCode == .lifetimeUniqueRegion }.count == 2)
        #expect(Set(live.filter { $0.reasonCode == .lifetimeUniqueRegion }.map(\.itemId)) == ["CA", "NY"])
        #expect(Set(live.filter { $0.reasonCode == .firstFindOfDay }.map(\.itemId)) == ["2026-08-10", "2026-08-11"])
    }

    @Test func rejectedFindClawsBackItsOwnBonusesOnly() throws {
        _ = try makeContext()
        let sessionId = UUID()
        let gameId = UUID()
        let events = MockTripActivityEventRepository()
        let games = MockGameInstanceRepository()
        let trips = MockTripSessionRepository()
        seedSoloCollaborativeTrip(
            sessionId: sessionId,
            gameId: gameId,
            participantId: consentedUid,
            games: games,
            trips: trips
        )

        let accepted = regionFoundEvent(
            id: "ok-CA",
            sessionId: sessionId,
            gameId: gameId,
            regionId: "CA",
            participantId: consentedUid,
            dayKey: "2026-08-10"
        )
        let rejected = regionFoundEvent(
            id: "dup-NY",
            sessionId: sessionId,
            gameId: gameId,
            regionId: "NY",
            participantId: consentedUid,
            dayKey: "2026-08-10",
            timestamp: Date().addingTimeInterval(1)
        )
        try events.append(accepted)
        try events.append(rejected)
        let svc = makeService(events: events, games: games, trips: trips)
        svc.handleCommittedActivityEvent(accepted)
        svc.handleCommittedActivityEvent(rejected)

        try svc.consumeResolution(
            DiscoveryResolution(
                resolutionId: "xp_res:v1:dup-NY:rejected_duplicate",
                sourceEventId: "dup-NY",
                sessionId: sessionId,
                gameInstanceId: gameId,
                itemId: "NY",
                actorUserId: consentedUid,
                finalOutcome: .rejectedDuplicate,
                tripScoringOutcome: .rejectedDuplicate,
                personalHistoryOutcome: .rejectedDuplicate,
                finalXpAward: 0,
                xpReason: .duplicateNoXp
            ),
            gameMode: .collaborative,
            tripMode: .solo
        )

        let live = try liveRows(forUserId: consentedUid)
        // NY's lifetime-first is gone; CA's survives, and so does the day bonus the accepted find earned.
        #expect(Set(live.filter { $0.reasonCode == .lifetimeUniqueRegion }.map(\.itemId)) == ["CA"])
        #expect(live.filter { $0.reasonCode == .firstFindOfDay }.count == 1)
        #expect(live.first { $0.reasonCode == .firstFindOfDay }?.sourceEventId == "ok-CA")
    }

    // MARK: - Day-key semantics (must match the server's, incl. FR-28h staleness)

    @Test func dayKeyPrefersTheStampedValueAndNeverReadsAsToday() {
        let sessionId = UUID()
        let gameId = UUID()
        let stamped = regionFoundEvent(
            id: "stamped",
            sessionId: sessionId,
            gameId: gameId,
            regionId: "CA",
            participantId: consentedUid,
            dayKey: "2026-08-01",
            timestamp: Date()
        )
        #expect(XpReconciliationService.xpDayKey(for: stamped) == "2026-08-01")

        var todayUTC = Calendar(identifier: .gregorian)
        todayUTC.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let parts = todayUTC.dateComponents([.year, .month, .day], from: Date())
        let today = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        #expect(XpReconciliationService.xpDayKey(for: stamped) != today)
    }

    @Test func dayKeyFallsBackToTheEventsOwnUtcDayNotNow() {
        let sessionId = UUID()
        let gameId = UUID()
        // 2026-08-01T23:30:00Z
        let timestamp = Date(timeIntervalSince1970: 1_785_713_400)
        let unstamped = regionFoundEvent(
            id: "unstamped",
            sessionId: sessionId,
            gameId: gameId,
            regionId: "CA",
            participantId: consentedUid,
            dayKey: nil,
            timestamp: timestamp
        )
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let parts = utc.dateComponents([.year, .month, .day], from: timestamp)
        let expected = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        #expect(XpReconciliationService.xpDayKey(for: unstamped) == expected)
    }

    @Test func malformedStampedDayKeyIsRejectedInFavourOfTheEventDay() {
        let sessionId = UUID()
        let gameId = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_785_713_400)
        let bogus = regionFoundEvent(
            id: "bogus",
            sessionId: sessionId,
            gameId: gameId,
            regionId: "CA",
            participantId: consentedUid,
            dayKey: "2026-8-1",
            timestamp: timestamp
        )
        #expect(XpReconciliationService.xpDayKey(for: bogus) != "2026-8-1")
    }

    // MARK: - The defect itself, at the repository layer

    /// The exact on-disk shape `LocalPlayIdentityRepository` leaves behind: `userId` rebound to the
    /// new uid, `xpUniquenessKey` still naming the retired device UUID.
    ///
    /// Every idempotency operation in `XpLedgerRepository` is key equality, so before the repair
    /// each of these three saw "no existing award" and the discovery got a second one. This is the
    /// single assertion that fails if the repair is ever removed.
    @Test func staleKeyLeftByTheRebindIsStillRecognisedAsTheSameAward() throws {
        let ctx = try makeContext()
        let sessionId = UUID()
        let gameId = UUID()

        let retiredKey = XpLedgerKeyBuilder.uniquenessKey(
            userId: localPlayId,
            sessionId: sessionId,
            gameInstanceId: gameId,
            itemId: "CA",
            xpCategory: .baseRegionDiscovery
        ).storageString
        try XpLedgerRepository.shared.append(
            XpLedgerEvent(
                userId: localPlayId,
                sessionId: sessionId,
                gameInstanceId: gameId,
                sourceEventId: "find-CA",
                sourceEventType: TripActivityEventKind.regionFound.rawValue,
                itemId: "CA",
                grantKind: .provisionalDiscoveryXp,
                status: .provisional,
                xpDelta: GameProgressionXPRewards.baseDiscoveryXp,
                reasonCode: .soloNewDiscovery,
                xpUniquenessKey: retiredKey
            )
        )
        // The rebind: userId only.
        for row in try ctx.fetch(FetchDescriptor<XpLedgerEventEntity>()) where row.userId == localPlayId {
            row.userId = consentedUid
        }
        try ctx.save()

        let consentedKey = XpLedgerKeyBuilder.uniquenessKey(
            userId: consentedUid,
            sessionId: sessionId,
            gameInstanceId: gameId,
            itemId: "CA",
            xpCategory: .baseRegionDiscovery
        ).storageString

        // 1. The absent-check must see the existing award and refuse a second one.
        let inserted = try XpLedgerRepository.shared.appendBaseDiscoveryIfAbsent(
            XpLedgerEvent(
                userId: consentedUid,
                sessionId: sessionId,
                gameInstanceId: gameId,
                sourceEventId: "find-CA",
                sourceEventType: TripActivityEventKind.regionFound.rawValue,
                itemId: "CA",
                grantKind: .provisionalDiscoveryXp,
                status: .provisional,
                xpDelta: GameProgressionXPRewards.baseDiscoveryXp,
                reasonCode: .soloNewDiscovery,
                xpUniquenessKey: consentedKey
            )
        )
        #expect(inserted == false)
        #expect(try liveRows(forUserId: consentedUid).count == 1)

        // 2. The lookup must find it under the identity that now owns it.
        #expect(try XpLedgerRepository.shared.ledgerEvents(forUniquenessKey: consentedKey).count == 1)

        // 3. Settlement must be able to close it.
        let voided = try XpLedgerRepository.shared.voidProvisionalRows(
            forUniquenessKey: consentedKey,
            resolvedAt: Date()
        )
        #expect(voided == GameProgressionXPRewards.baseDiscoveryXp)
        #expect(try liveRows(forUserId: consentedUid).isEmpty)
    }

    /// The repair must never touch a row belonging to a different award slot or a different user.
    @Test func repairLeavesUnrelatedRowsAlone() throws {
        _ = try makeContext()
        let sessionId = UUID()
        let gameId = UUID()

        let otherRegionKey = XpLedgerKeyBuilder.uniquenessKey(
            userId: localPlayId,
            sessionId: sessionId,
            gameInstanceId: gameId,
            itemId: "NY",
            xpCategory: .baseRegionDiscovery
        ).storageString
        try XpLedgerRepository.shared.append(
            XpLedgerEvent(
                userId: consentedUid,
                sessionId: sessionId,
                gameInstanceId: gameId,
                sourceEventId: "find-NY",
                sourceEventType: TripActivityEventKind.regionFound.rawValue,
                itemId: "NY",
                grantKind: .provisionalDiscoveryXp,
                status: .provisional,
                xpDelta: GameProgressionXPRewards.baseDiscoveryXp,
                reasonCode: .soloNewDiscovery,
                xpUniquenessKey: otherRegionKey
            )
        )

        let caKey = XpLedgerKeyBuilder.uniquenessKey(
            userId: consentedUid,
            sessionId: sessionId,
            gameInstanceId: gameId,
            itemId: "CA",
            xpCategory: .baseRegionDiscovery
        ).storageString
        #expect(try XpLedgerRepository.shared.ledgerEvents(forUniquenessKey: caKey).isEmpty)
        // NY's row keeps its own (stale) key: different slot, so it is not this award.
        #expect(try XpLedgerRepository.shared.ledgerEvents(forUniquenessKey: otherRegionKey).count == 1)
    }

    // MARK: - Uniqueness-key parsing (the rebind-stable slot)

    @Test func uniquenessKeyRoundTripsThroughParse() {
        let key = XpUniquenessKey(
            userId: consentedUid,
            sessionId: UUID(),
            gameInstanceId: UUID(),
            itemId: "CA",
            xpCategory: .baseRegionDiscovery
        )
        let parsed = XpUniquenessKey.parse(storageString: key.storageString)
        #expect(parsed == key)
        #expect(parsed?.slot == key.slot)
    }

    @Test func slotIsIdentityIndependent() {
        let sessionId = UUID()
        let gameId = UUID()
        let local = XpUniquenessKey(
            userId: localPlayId,
            sessionId: sessionId,
            gameInstanceId: gameId,
            itemId: "CA",
            xpCategory: .baseRegionDiscovery
        )
        let consented = XpUniquenessKey(
            userId: consentedUid,
            sessionId: sessionId,
            gameInstanceId: gameId,
            itemId: "CA",
            xpCategory: .baseRegionDiscovery
        )
        #expect(local.slot == consented.slot)
        #expect(local.storageString != consented.storageString)
    }

    @Test func parseRejectsNonCanonicalStrings() {
        #expect(XpUniquenessKey.parse(storageString: "") == nil)
        #expect(XpUniquenessKey.parse(storageString: "xp|v1|u1|not-a-uuid|not-a-uuid|CA|base_region_discovery") == nil)
        #expect(XpUniquenessKey.parse(storageString: "xp|v2|u1|\(UUID().uuidString)|\(UUID().uuidString)|CA|base_region_discovery") == nil)
        #expect(XpUniquenessKey.parse(
            storageString: "xp|v1|u1|\(UUID().uuidString)|\(UUID().uuidString)|CA|not_a_category"
        ) == nil)
    }
}
