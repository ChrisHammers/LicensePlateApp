//
//  GameScopedActivityEventTests.swift
//  LicensePlateAppTests
//
//  Step 6.9.5 Phase A — Trip activity event contract and game-scoped replay (no session id as game id).
//

import Foundation
import Testing
@testable import LicensePlateApp

struct GameScopedActivityEventTests {

    @Test func tripSessionIdMatchesSessionId() {
        let sid = UUID()
        let event = TripActivityEvent(sessionId: sid, kind: .tripStarted, actorId: "user1")
        #expect(event.tripSessionId == sid)
        #expect(event.tripSessionId == event.sessionId)
    }
}

@MainActor
struct GameScopedActivityEventMockRepositoryTests {

    @Test func discoveriesAllGames_twoGamesSameRegion_keepsBoth() throws {
        let mock = MockTripActivityEventRepository()
        let sessionId = UUID()
        let game1 = UUID()
        let game2 = UUID()
        let list = FoundRegion.InputMethod.list.rawValue
        try mock.append(TripActivityEvent(
            sessionId: sessionId,
            kind: .regionFound,
            payload: [
                TripActivityEventPayloadKey.regionId: "CA",
                TripActivityEventPayloadKey.gameInstanceId: game1.uuidString,
                TripActivityEventPayloadKey.inputMethod: list
            ]
        ))
        try mock.append(TripActivityEvent(
            sessionId: sessionId,
            kind: .regionFound,
            payload: [
                TripActivityEventPayloadKey.regionId: "CA",
                TripActivityEventPayloadKey.gameInstanceId: game2.uuidString,
                TripActivityEventPayloadKey.inputMethod: list
            ]
        ))
        let discoveries = try mock.discoveries(sessionId: sessionId, gameInstanceId: nil)
        #expect(discoveries.count == 2)
        let gameIds = Set(discoveries.map(\.gameInstanceId))
        #expect(gameIds == Set([game1, game2]))
        #expect(discoveries.allSatisfy { $0.targetId == "CA" })
    }

    @Test func discoveriesAllGames_regionFoundWithoutGameInstanceId_isSkipped() throws {
        let mock = MockTripActivityEventRepository()
        let sessionId = UUID()
        try mock.append(TripActivityEvent(
            sessionId: sessionId,
            kind: .regionFound,
            payload: [
                TripActivityEventPayloadKey.regionId: "CA",
                TripActivityEventPayloadKey.inputMethod: FoundRegion.InputMethod.list.rawValue
            ]
        ))
        let discoveries = try mock.discoveries(sessionId: sessionId, gameInstanceId: nil)
        #expect(discoveries.isEmpty)
    }

    @Test func discoveriesAllGames_doesNotUseSessionIdAsGameInstanceId() throws {
        let mock = MockTripActivityEventRepository()
        let sessionId = UUID()
        try mock.append(TripActivityEvent(
            sessionId: sessionId,
            kind: .regionFound,
            payload: [
                TripActivityEventPayloadKey.regionId: "TX",
                TripActivityEventPayloadKey.inputMethod: FoundRegion.InputMethod.list.rawValue
            ]
        ))
        let discoveries = try mock.discoveries(sessionId: sessionId, gameInstanceId: nil)
        #expect(discoveries.allSatisfy { $0.gameInstanceId != sessionId })
    }

    @Test func discoveriesFilteredByGame_usesFilterWhenPayloadOmitsGameInstanceId() throws {
        let mock = MockTripActivityEventRepository()
        let sessionId = UUID()
        let gameId = UUID()
        try mock.append(TripActivityEvent(
            sessionId: sessionId,
            kind: .regionFound,
            payload: [
                TripActivityEventPayloadKey.regionId: "OR",
                TripActivityEventPayloadKey.inputMethod: FoundRegion.InputMethod.voice.rawValue
            ]
        ))
        let discoveries = try mock.discoveries(sessionId: sessionId, gameInstanceId: gameId)
        #expect(discoveries.count == 1)
        #expect(discoveries[0].gameInstanceId == gameId)
        #expect(discoveries[0].targetId == "OR")
    }
}
