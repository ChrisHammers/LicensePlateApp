//
//  TripSessionLifecycleServiceTests.swift
//  LicensePlateAppTests
//
//  Step 04 — TripSessionLifecycleService: startTrip, endTrip, resetTrip, cancelSession.
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
            status: .active,
            mode: .solo,
            createdAt: Date(),
            createdBy: "user1",
            startedAt: nil,
            participants: [TripParticipant(userId: "user1", role: .owner, joinedAt: Date())],
            teams: [],
            enabledCountryRawValues: ["United States"]
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
        let service = TripSessionLifecycleService(
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            syncCoordinator: syncCoordinator
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
            participants: [TripParticipant(userId: "user1", role: .owner, joinedAt: Date())],
            teams: [],
            enabledCountryRawValues: ["United States"]
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
        let service = TripSessionLifecycleService(
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            syncCoordinator: syncCoordinator
        )

        try service.endTrip(sessionId: sessionId, endedBy: "user1")

        let updatedSession = try sessionRepo.session(byId: sessionId)
        #expect(updatedSession?.endedAt != nil)
        #expect(updatedSession?.status == .ended)

        let appended = eventRepo.appendedEvents()
        #expect(appended.contains { $0.kind == .tripEnded })
        #expect(appended.contains { $0.kind == .gameEnded })
    }

    @Test func resetTripDeletesEventsAndClearsSessionDates() async throws {
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
            endedAt: nil,
            endedBy: nil,
            participants: [],
            teams: [],
            enabledCountryRawValues: ["United States"]
        )
        sessionRepo.seed(session)
        try eventRepo.append(TripActivityEvent(sessionId: sessionId, kind: .regionFound, payload: [TripActivityEventPayloadKey.regionId: "CA", TripActivityEventPayloadKey.gameInstanceId: gameId.uuidString]))

        let syncCoordinator = MockSyncCoordinator()
        let service = TripSessionLifecycleService(
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            syncCoordinator: syncCoordinator
        )

        try service.resetTrip(sessionId: sessionId, gameInstanceId: gameId)

        let updatedSession = try sessionRepo.session(byId: sessionId)
        #expect(updatedSession?.startedAt == nil)
        #expect(updatedSession?.endedAt == nil)

        let regions = try eventRepo.foundRegions(sessionId: sessionId, gameInstanceId: gameId)
        #expect(regions.isEmpty)
    }

    @Test func cancelSessionSetsCancelledAndEndedAt() async throws {
        let sessionRepo = MockTripSessionRepository()
        let gameRepo = MockGameInstanceRepository()
        let eventRepo = MockTripActivityEventRepository()

        let sessionId = UUID()
        let session = TripSession(
            id: sessionId,
            name: "Test",
            status: .active,
            mode: .solo,
            createdAt: Date(),
            createdBy: "user1",
            startedAt: Date(),
            participants: [],
            teams: [],
            enabledCountryRawValues: ["United States"]
        )
        sessionRepo.seed(session)

        let syncCoordinator = MockSyncCoordinator()
        let service = TripSessionLifecycleService(
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            syncCoordinator: syncCoordinator
        )

        try service.cancelSession(sessionId: sessionId, cancelledBy: "user1")

        let updatedSession = try sessionRepo.session(byId: sessionId)
        #expect(updatedSession?.status == .cancelled)
        #expect(updatedSession?.endedAt != nil)
    }
}
