//
//  TripSummarySeparationTests.swift
//  LicensePlateAppTests
//
//  Step 6.9.6 Phase A — Trip-level vs game-level fields on TripSummary / TripSummaryGameItem.
//

import Foundation
import Testing
@testable import LicensePlateApp

struct TripSummarySeparationTests {

    @Test func tripModeOnSummaryMatchesSessionNotGameMode() async throws {
        let sessionId = UUID()
        let gameId = UUID()
        let session = TripSession(
            id: sessionId,
            name: "Multiplayer trip",
            status: .ended,
            createdAt: Date(),
            participants: [
                TripParticipant(userId: "u1", role: .owner),
                TripParticipant(userId: "u2", role: .member)
            ]
        )
        var config = CommonGameConfig()
        config.gameMode = .competitive
        let game = GameInstance(
            id: gameId,
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: GameType.licensePlate.rawValue),
            commonConfig: config
        )
        let summary = TripSummaryBuilder.build(session: session, games: [game], discoveries: [], credits: [])
        #expect(summary.tripMode == .multiplayer)
        #expect(summary.games[0].gameMode == .competitive)
    }

    @Test func soloTripCanHaveCollaborativeGame() async throws {
        let sessionId = UUID()
        let gameId = UUID()
        let session = TripSession(
            id: sessionId,
            name: "Solo",
            status: .ended,
            createdAt: Date(),
            participants: [TripParticipant(userId: "u1", role: .owner)]
        )
        let game = GameInstance(
            id: gameId,
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: GameType.licensePlate.rawValue)
        )
        let summary = TripSummaryBuilder.build(session: session, games: [game], discoveries: [], credits: [])
        #expect(summary.tripMode == .solo)
        #expect(summary.games[0].gameMode == .collaborative)
    }

    @Test func tripModeLocalizedDisplayNameIsNonEmpty() async throws {
        #expect(TripMode.solo.localizedDisplayName.isEmpty == false)
        #expect(TripMode.multiplayer.localizedDisplayName.isEmpty == false)
    }

    @Test func gameModeLocalizedDisplayNameIsNonEmpty() async throws {
        #expect(GameMode.collaborative.localizedDisplayName.isEmpty == false)
        #expect(GameMode.competitive.localizedDisplayName.isEmpty == false)
    }
}
