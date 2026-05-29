//
//  XpReconciliationServiceTests.swift
//  LicensePlateAppTests
//

import Foundation
import SwiftData
import Testing
@testable import LicensePlateApp

@MainActor
struct XpReconciliationServiceTests {

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
            tripSessionRepository: trips
        )
    }

    private func regionFoundEvent(
        id: String,
        sessionId: UUID,
        gameId: UUID,
        regionId: String,
        participantId: String
    ) -> TripActivityEvent {
        TripActivityEvent(
            id: id,
            sessionId: sessionId,
            kind: .regionFound,
            actorId: participantId,
            payload: [
                TripActivityEventPayloadKey.regionId: regionId,
                TripActivityEventPayloadKey.gameInstanceId: gameId.uuidString,
                TripActivityEventPayloadKey.participantId: participantId,
                TripActivityEventPayloadKey.inputMethod: FoundRegion.InputMethod.list.rawValue,
            ]
        )
    }

    @Test func competitiveFirstFinderWritesProvisionalPlus10() throws {
        _ = try makeContext()
        let sessionId = UUID()
        let gameId = UUID()
        let events = MockTripActivityEventRepository()
        let games = MockGameInstanceRepository()
        let trips = MockTripSessionRepository()
        let session = TripSession(
            id: sessionId,
            name: "T",
            participants: [
                TripParticipant(userId: "u1", role: .owner, joinedAt: Date()),
                TripParticipant(userId: "u2", role: .member, joinedAt: Date()),
            ]
        )
        trips.seed(session)
        let cc = CommonGameConfig(
            lifecycleState: .started,
            gameMode: .competitive,
            configLocked: true,
            configLockReason: .gameStarted
        )
        let game = GameInstance(
            id: gameId,
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: "license_plate"),
            commonConfig: cc
        )
        games.seed(game)

        let ev = regionFoundEvent(id: "find-1", sessionId: sessionId, gameId: gameId, regionId: "TX", participantId: "u1")
        try events.append(ev)

        let svc = makeService(events: events, games: games, trips: trips)
        svc.handleCommittedActivityEvent(ev)

        let rows = try XpLedgerRepository.shared.ledgerEvents(
            userId: "u1",
            sessionId: sessionId,
            gameInstanceId: gameId,
            itemId: "TX",
            statuses: nil
        )
        #expect(rows.count == 1)
        #expect(rows[0].grantKind == .provisionalDiscoveryXp)
        #expect(rows[0].xpDelta == 10)
    }

    @Test func consumeAcceptedFirstKeepsNet10() throws {
        _ = try makeContext()
        let sessionId = UUID()
        let gameId = UUID()
        try competitiveProvisionalSeed(sessionId: sessionId, gameId: gameId)

        let resolution = DiscoveryResolution(
            resolutionId: "xp_res:v1:find-1:accepted_first",
            sourceEventId: "find-1",
            sessionId: sessionId,
            gameInstanceId: gameId,
            itemId: "TX",
            actorUserId: "u1",
            finalOutcome: .acceptedFirst,
            tripScoringOutcome: .acceptedFirst,
            personalHistoryOutcome: .acceptedFirst,
            finalXpAward: 10,
            xpReason: .competitiveFirstFinder
        )
        let events = MockTripActivityEventRepository()
        let games = MockGameInstanceRepository()
        let trips = MockTripSessionRepository()
        seedCompetitiveGame(sessionId: sessionId, gameId: gameId, games: games, trips: trips)

        let svc = makeService(events: events, games: games, trips: trips)
        try svc.consumeResolution(resolution, gameMode: .competitive, tripMode: .multiplayer)

        let key = XpLedgerKeyBuilder.uniquenessKey(
            userId: "u1",
            sessionId: sessionId,
            gameInstanceId: gameId,
            itemId: "TX",
            xpCategory: .baseRegionDiscovery
        ).storageString
        let rows = try XpLedgerRepository.shared.ledgerEvents(forUniquenessKey: key)
        #expect(rows.count == 1)
        #expect(rows.reduce(0) { $0 + $1.xpDelta } == 10)
    }

    @Test func consumeAcceptedLateDoesNotClawBackBaseXp() throws {
        _ = try makeContext()
        let sessionId = UUID()
        let gameId = UUID()
        try competitiveProvisionalSeed(sessionId: sessionId, gameId: gameId)

        let events = MockTripActivityEventRepository()
        let games = MockGameInstanceRepository()
        let trips = MockTripSessionRepository()
        seedCompetitiveGame(sessionId: sessionId, gameId: gameId, games: games, trips: trips)

        let resolution = DiscoveryResolution(
            resolutionId: "xp_res:v1:find-1:accepted_late",
            sourceEventId: "find-1",
            sessionId: sessionId,
            gameInstanceId: gameId,
            itemId: "TX",
            actorUserId: "u1",
            finalOutcome: .acceptedLate,
            tripScoringOutcome: .acceptedLate,
            personalHistoryOutcome: .acceptedLate,
            finalXpAward: GameProgressionXPRewards.baseDiscoveryXp,
            xpReason: .competitiveLateFinder
        )
        let svc = makeService(events: events, games: games, trips: trips)
        try svc.consumeResolution(resolution, gameMode: .competitive, tripMode: .multiplayer)

        let key = XpLedgerKeyBuilder.uniquenessKey(
            userId: "u1",
            sessionId: sessionId,
            gameInstanceId: gameId,
            itemId: "TX",
            xpCategory: .baseRegionDiscovery
        ).storageString
        let rows = try XpLedgerRepository.shared.ledgerEvents(forUniquenessKey: key)
        let net = rows.reduce(0) { $0 + $1.xpDelta }
        #expect(net == GameProgressionXPRewards.baseDiscoveryXp)
        #expect(rows.contains { $0.grantKind == .reconciliationAdjustment && $0.xpDelta < 0 } == false)
    }

    @Test func consumeRejectedDuplicateDoesNotClawBackPreviouslyGrantedXp() throws {
        _ = try makeContext()
        let sessionId = UUID()
        let gameId = UUID()
        try competitiveProvisionalSeed(sessionId: sessionId, gameId: gameId)

        let events = MockTripActivityEventRepository()
        let games = MockGameInstanceRepository()
        let trips = MockTripSessionRepository()
        seedCompetitiveGame(sessionId: sessionId, gameId: gameId, games: games, trips: trips)

        let resolution = DiscoveryResolution(
            resolutionId: "xp_res:v1:find-1:rejected_duplicate",
            sourceEventId: "find-1",
            sessionId: sessionId,
            gameInstanceId: gameId,
            itemId: "TX",
            actorUserId: "u1",
            finalOutcome: .rejectedDuplicate,
            tripScoringOutcome: .rejectedDuplicate,
            personalHistoryOutcome: .rejectedDuplicate,
            finalXpAward: 0,
            xpReason: .duplicateNoXp
        )
        let svc = makeService(events: events, games: games, trips: trips)
        try svc.consumeResolution(resolution, gameMode: .competitive, tripMode: .multiplayer)

        let key = XpLedgerKeyBuilder.uniquenessKey(
            userId: "u1",
            sessionId: sessionId,
            gameInstanceId: gameId,
            itemId: "TX",
            xpCategory: .baseRegionDiscovery
        ).storageString
        let rows = try XpLedgerRepository.shared.ledgerEvents(forUniquenessKey: key)
        let net = rows.reduce(0) { $0 + $1.xpDelta }
        #expect(net == GameProgressionXPRewards.baseDiscoveryXp)
        #expect(rows.contains { $0.grantKind == .reconciliationAdjustment && $0.xpDelta < 0 } == false)
    }

    @Test func secondCompetitiveFindSameUserDoesNotMintMoreBaseXp() throws {
        _ = try makeContext()
        let sessionId = UUID()
        let gameId = UUID()
        let events = MockTripActivityEventRepository()
        let games = MockGameInstanceRepository()
        let trips = MockTripSessionRepository()
        seedCompetitiveGame(sessionId: sessionId, gameId: gameId, games: games, trips: trips)

        let ev1 = regionFoundEvent(id: "find-1", sessionId: sessionId, gameId: gameId, regionId: "TX", participantId: "u1")
        let ev2 = regionFoundEvent(
            id: "find-2",
            sessionId: sessionId,
            gameId: gameId,
            regionId: "TX",
            participantId: "u1"
        )
        try events.append(ev1)
        try events.append(ev2)

        let svc = makeService(events: events, games: games, trips: trips)
        svc.handleCommittedActivityEvent(ev1)
        svc.handleCommittedActivityEvent(ev2)

        let rows = try XpLedgerRepository.shared.ledgerEvents(
            userId: "u1",
            sessionId: sessionId,
            gameInstanceId: gameId,
            itemId: "TX",
            statuses: nil
        )
        #expect(rows.count == 1)
    }

    @Test func soloTripWritesFinalDiscoveryXpImmediately() throws {
        _ = try makeContext()
        let sessionId = UUID()
        let gameId = UUID()
        let events = MockTripActivityEventRepository()
        let games = MockGameInstanceRepository()
        let trips = MockTripSessionRepository()
        let session = TripSession(
            id: sessionId,
            name: "Solo",
            participants: [TripParticipant(userId: "u1", role: .owner, joinedAt: Date())]
        )
        trips.seed(session)
        let cc = CommonGameConfig(
            lifecycleState: .started,
            gameMode: .competitive,
            configLocked: true,
            configLockReason: .gameStarted
        )
        let game = GameInstance(
            id: gameId,
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: "license_plate"),
            commonConfig: cc
        )
        games.seed(game)

        let ev = regionFoundEvent(id: "solo-1", sessionId: sessionId, gameId: gameId, regionId: "NY", participantId: "u1")
        try events.append(ev)

        let svc = makeService(events: events, games: games, trips: trips)
        svc.handleCommittedActivityEvent(ev)

        let rows = try XpLedgerRepository.shared.ledgerEvents(
            userId: "u1",
            sessionId: sessionId,
            gameInstanceId: gameId,
            itemId: "NY",
            statuses: nil
        )
        #expect(rows.count == 1)
        #expect(rows[0].grantKind == .finalDiscoveryAward)
        #expect(rows[0].reasonCode == .soloNewDiscovery)
    }

    @Test func consumeResolutionIsIdempotentPerResolutionId() throws {
        _ = try makeContext()
        let sessionId = UUID()
        let gameId = UUID()
        try competitiveProvisionalSeed(sessionId: sessionId, gameId: gameId)

        let events = MockTripActivityEventRepository()
        let games = MockGameInstanceRepository()
        let trips = MockTripSessionRepository()
        seedCompetitiveGame(sessionId: sessionId, gameId: gameId, games: games, trips: trips)

        let resolution = DiscoveryResolution(
            resolutionId: "xp_res:v1:find-1:accepted_late",
            sourceEventId: "find-1",
            sessionId: sessionId,
            gameInstanceId: gameId,
            itemId: "TX",
            actorUserId: "u1",
            finalOutcome: .acceptedLate,
            tripScoringOutcome: .acceptedLate,
            personalHistoryOutcome: .acceptedLate,
            finalXpAward: GameProgressionXPRewards.baseDiscoveryXp,
            xpReason: .competitiveLateFinder
        )
        let svc = makeService(events: events, games: games, trips: trips)
        try svc.consumeResolution(resolution, gameMode: .competitive, tripMode: .multiplayer)
        try svc.consumeResolution(resolution, gameMode: .competitive, tripMode: .multiplayer)

        let key = XpLedgerKeyBuilder.uniquenessKey(
            userId: "u1",
            sessionId: sessionId,
            gameInstanceId: gameId,
            itemId: "TX",
            xpCategory: .baseRegionDiscovery
        ).storageString
        let adjustments = try XpLedgerRepository.shared.ledgerEvents(forUniquenessKey: key)
            .filter { $0.grantKind == .reconciliationAdjustment }
        #expect(adjustments.count == 1)
    }

    @Test func collaborativeMultiplayerWritesFinalPlus10() throws {
        _ = try makeContext()
        let sessionId = UUID()
        let gameId = UUID()
        let events = MockTripActivityEventRepository()
        let games = MockGameInstanceRepository()
        let trips = MockTripSessionRepository()
        let session = TripSession(
            id: sessionId,
            name: "T",
            participants: [
                TripParticipant(userId: "u1", role: .owner, joinedAt: Date()),
                TripParticipant(userId: "u2", role: .member, joinedAt: Date()),
            ]
        )
        trips.seed(session)
        let cc = CommonGameConfig(
            lifecycleState: .started,
            gameMode: .collaborative,
            configLocked: true,
            configLockReason: .gameStarted
        )
        let game = GameInstance(
            id: gameId,
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: "license_plate"),
            commonConfig: cc
        )
        games.seed(game)

        let ev = regionFoundEvent(id: "find-1", sessionId: sessionId, gameId: gameId, regionId: "CA", participantId: "u1")
        try events.append(ev)

        let svc = makeService(events: events, games: games, trips: trips)
        svc.handleCommittedActivityEvent(ev)

        let rows = try XpLedgerRepository.shared.ledgerEvents(
            userId: "u1",
            sessionId: sessionId,
            gameInstanceId: gameId,
            itemId: "CA",
            statuses: nil
        )
        #expect(rows.count == 1)
        #expect(rows[0].grantKind == .finalDiscoveryAward)
        #expect(rows[0].status == .final)
    }

    // MARK: - Seeds

    private func competitiveProvisionalSeed(sessionId: UUID, gameId: UUID) throws {
        let key = XpLedgerKeyBuilder.uniquenessKey(
            userId: "u1",
            sessionId: sessionId,
            gameInstanceId: gameId,
            itemId: "TX",
            xpCategory: .baseRegionDiscovery
        ).storageString
        let provisional = XpLedgerEvent(
            userId: "u1",
            sessionId: sessionId,
            gameInstanceId: gameId,
            sourceEventId: "find-1",
            sourceEventType: TripActivityEventKind.regionFound.rawValue,
            itemId: "TX",
            grantKind: .provisionalDiscoveryXp,
            status: .provisional,
            xpDelta: 10,
            reasonCode: .discoveryClaimPendingResolution,
            xpUniquenessKey: key,
            metadata: [XpLedgerMetadataKey.originalDiscoveryEventId: "find-1"]
        )
        _ = try XpLedgerRepository.shared.appendBaseDiscoveryIfAbsent(provisional)
    }

    private func seedCompetitiveGame(
        sessionId: UUID,
        gameId: UUID,
        games: MockGameInstanceRepository,
        trips: MockTripSessionRepository
    ) {
        let session = TripSession(
            id: sessionId,
            name: "T",
            participants: [
                TripParticipant(userId: "u1", role: .owner, joinedAt: Date()),
                TripParticipant(userId: "u2", role: .member, joinedAt: Date()),
            ]
        )
        trips.seed(session)
        let cc = CommonGameConfig(
            lifecycleState: .started,
            gameMode: .competitive,
            configLocked: true,
            configLockReason: .gameStarted
        )
        let game = GameInstance(
            id: gameId,
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: "license_plate"),
            commonConfig: cc
        )
        games.seed(game)
    }
}
