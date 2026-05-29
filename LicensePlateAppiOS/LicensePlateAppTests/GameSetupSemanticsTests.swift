//
//  GameSetupSemanticsTests.swift
//  LicensePlateAppTests
//
//  Step 6.9.4 — GameMode and teams come from assembly choices, not from trip participation (roster size).
//

import Foundation
import Testing
@testable import LicensePlateApp

struct GameSetupSemanticsTests {

    private func makeSession(participants: [TripParticipant]) -> TripSession {
        let created = Date()
        return TripSession(
            id: UUID(),
            name: "Test",
            status: .active,
            createdAt: created,
            createdBy: "user1",
            startedAt: created,
            endedAt: nil,
            participants: participants
        )
    }

    @Test func sameChoicesYieldSameGameModeRegardlessOfTripMode() async throws {
        let config = CombinedGameConfiguration(enabledGameTypes: [.licensePlate])
        let choices: [GameType: GameSetupChoice] = [
            .licensePlate: GameSetupChoice(gameType: .licensePlate, gameMode: .competitive, teams: [])
        ]

        let soloSession = makeSession(participants: [TripParticipant(userId: "user1", role: .owner)])
        let multiSession = makeSession(participants: [
            TripParticipant(userId: "user1", role: .owner),
            TripParticipant(userId: "user2", role: .member)
        ])

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
