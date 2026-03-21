//
//  TripSessionLifecycleServiceTests.swift
//  LicensePlateAppTests
//
//  Step 04 / 6.9.3 — TripSessionLifecycleService: startTrip, endTrip, cancelSession (game reset → GameInstanceLifecycleServiceTests).
//

import Foundation
import SwiftData
import Testing
@testable import LicensePlateApp

@MainActor
struct TripSessionLifecycleServiceTests {

    @Test func startTripCallsTransitionAndAppendsEvents() async throws {
        let sessionRepo = MockTripSessionRepository()
        let gameRepo = MockGameInstanceRepository()
        let eventRepo = MockTripActivityEventRepository()

        let sessionId = UUID()
        let gameId = UUID()
        let session = TripSession(
            id: sessionId,
            name: "Test",
            status: .created,
            mode: .solo,
            createdAt: Date(),
            createdBy: "user1",
            startedAt: nil,
            participants: [TripParticipant(userId: "user1", role: .owner, joinedAt: Date())]
        )
        sessionRepo.seed(session)

        var game = GameInstance(
            id: gameId,
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: "license_plate"),
            commonConfig: CommonGameConfig(lifecycleState: .created, configLocked: false, configLockReason: .none)
        )
        gameRepo.seed(game)

        let syncCoordinator = MockSyncCoordinator()
        let gameLifecycle = GameInstanceLifecycleService(
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            syncCoordinator: syncCoordinator
        )
        let service = TripSessionLifecycleService(
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            syncCoordinator: syncCoordinator,
            gameInstanceLifecycleService: gameLifecycle
        )

        try service.startTrip(sessionId: sessionId, actorId: "user1")

        let updatedSession = try sessionRepo.session(byId: sessionId)
        #expect(updatedSession?.startedAt != nil)
        #expect(updatedSession?.status == .active)

        let instances = try gameRepo.fetchByTripSession(sessionId: sessionId)
        #expect(instances.first?.commonConfig.lifecycleState == .started)
        #expect(instances.first?.commonConfig.configLockReason == .gameStarted)

        let appended = eventRepo.appendedEvents()
        #expect(appended.contains { $0.kind == .tripStarted })
        #expect(appended.contains { $0.kind == .gameStarted && $0.payload?[TripActivityEventPayloadKey.gameInstanceId] == gameId.uuidString })
    }

    @Test func endTripSetsEndedAndAppendsEvents() async throws {
        let sessionRepo = MockTripSessionRepository()
        let gameRepo = MockGameInstanceRepository()
        let eventRepo = MockTripActivityEventRepository()

        let sessionId = UUID()
        let gameId = UUID()
        let session = TripSession(
            id: sessionId,
            name: "Test",
            status: .active,
            mode: .solo,
            createdAt: Date(),
            createdBy: "user1",
            startedAt: Date(),
            participants: [TripParticipant(userId: "user1", role: .owner, joinedAt: Date())]
        )
        sessionRepo.seed(session)
        gameRepo.seed(GameInstance(
            id: gameId,
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: "license_plate"),
            commonConfig: CommonGameConfig(lifecycleState: .started, configLocked: true, configLockReason: .gameStarted)
        ))

        let syncCoordinator = MockSyncCoordinator()
        let gameLifecycle = GameInstanceLifecycleService(
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            syncCoordinator: syncCoordinator
        )
        let service = TripSessionLifecycleService(
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            syncCoordinator: syncCoordinator,
            gameInstanceLifecycleService: gameLifecycle
        )

        try service.endTrip(sessionId: sessionId, endedBy: "user1")

        let updatedSession = try sessionRepo.session(byId: sessionId)
        #expect(updatedSession?.endedAt != nil)
        #expect(updatedSession?.status == .ended)

        let appended = eventRepo.appendedEvents()
        #expect(appended.contains { $0.kind == .tripEnded })
        #expect(appended.contains { $0.kind == .gameEnded })

        let endedGame = try gameRepo.instance(byId: gameId)
        #expect(endedGame?.commonConfig.lifecycleState == .ended)
    }

    @Test func cancelSessionSetsCancelledEndedByAndClearsGamesAndEvents() async throws {
        let sessionRepo = MockTripSessionRepository()
        let gameRepo = MockGameInstanceRepository()
        let eventRepo = MockTripActivityEventRepository()

        let sessionId = UUID()
        let gameId = UUID()
        let session = TripSession(
            id: sessionId,
            name: "Test",
            status: .active,
            mode: .solo,
            createdAt: Date(),
            createdBy: "user1",
            startedAt: Date(),
            participants: []
        )
        sessionRepo.seed(session)
        gameRepo.seed(GameInstance(
            id: gameId,
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: "license_plate"),
            commonConfig: CommonGameConfig(lifecycleState: .started, configLocked: true, configLockReason: .gameStarted)
        ))
        try eventRepo.append(TripActivityEvent(sessionId: sessionId, kind: .tripStarted, actorId: "user1"))

        let syncCoordinator = MockSyncCoordinator()
        let gameLifecycle = GameInstanceLifecycleService(
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            syncCoordinator: syncCoordinator
        )
        let service = TripSessionLifecycleService(
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            syncCoordinator: syncCoordinator,
            gameInstanceLifecycleService: gameLifecycle
        )

        try service.cancelSession(sessionId: sessionId, cancelledBy: "user1")

        let updatedSession = try sessionRepo.session(byId: sessionId)
        #expect(updatedSession?.status == .cancelled)
        #expect(updatedSession?.endedAt != nil)
        #expect(updatedSession?.endedBy == "user1")

        let games = try gameRepo.fetchByTripSession(sessionId: sessionId)
        #expect(games.isEmpty)

        let remainingEvents = try eventRepo.events(sessionId: sessionId, limit: nil)
        #expect(remainingEvents.isEmpty)
    }
}
