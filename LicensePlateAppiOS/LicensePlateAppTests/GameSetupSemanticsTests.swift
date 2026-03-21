//
//  GameSetupSemanticsTests.swift
//  LicensePlateAppTests
//
//  Step 6.9.4 — GameMode and teams come from assembly choices, not TripSession.mode.
//

import Foundation
import Testing
@testable import LicensePlateApp

struct GameSetupSemanticsTests {

    private func makeSession(mode: TripMode) -> TripSession {
        let created = Date()
        return TripSession(
            id: UUID(),
            name: "Test",
            status: .active,
            mode: mode,
            createdAt: created,
            createdBy: "user1",
            startedAt: created,
            endedAt: nil,
            participants: [TripParticipant(userId: "user1", role: .owner)]
        )
    }

    @Test func sameChoicesYieldSameGameModeRegardlessOfTripMode() async throws {
        let config = CombinedGameConfiguration(enabledGameTypes: [.licensePlate])
        let choices: [GameType: GameSetupChoice] = [
            .licensePlate: GameSetupChoice(gameType: .licensePlate, gameMode: .competitive, teams: [])
        ]

        let soloSession = makeSession(mode: .solo)
        let multiSession = makeSession(mode: .multiplayer)

        let soloInstances = CombinedGameAssembler.assemble(
            session: soloSession,
            config: config,
            choicesByGameType: choices,
            licensePlateConfig: nil
        )
        let multiInstances = CombinedGameAssembler.assemble(
            session: multiSession,
            config: config,
            choicesByGameType: choices,
            licensePlateConfig: nil
        )

        #expect(soloInstances[0].commonConfig.gameMode == multiInstances[0].commonConfig.gameMode)
        #expect(soloInstances[0].commonConfig.gameMode == .competitive)
    }
}
