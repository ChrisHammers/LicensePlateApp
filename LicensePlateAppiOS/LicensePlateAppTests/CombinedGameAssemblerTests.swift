//
//  CombinedGameAssemblerTests.swift
//  LicensePlateAppTests
//
//  Step 06 — CombinedGameAssembler: one GameInstance per enabled game type; no persistence.
//

import Foundation
import Testing
@testable import LicensePlateApp

struct CombinedGameAssemblerTests {

    private func makeSession(
        id: UUID = UUID(),
        name: String = "Test Trip",
        status: TripSessionState = .active,
        mode: TripMode = .solo,
        startedAt: Date? = nil,
        endedAt: Date? = nil
    ) -> TripSession {
        let created = Date()
        return TripSession(
            id: id,
            name: name,
            status: status,
            mode: mode,
            createdAt: created,
            createdBy: "user1",
            startedAt: startedAt ?? created,
            endedAt: endedAt,
            participants: [TripParticipant(userId: "user1", role: .owner)]
        )
    }

    @Test func oneGameTypeReturnsOneInstance() async throws {
        let session = makeSession()
        let config = CombinedGameConfiguration(enabledGameTypes: [.licensePlate])
        let lpConfig = CombinedGameAssembler.licensePlateConfig(from: [.unitedStates, .canada])

        let instances = CombinedGameAssembler.assemble(session: session, config: config, licensePlateConfig: lpConfig)

        #expect(instances.count == 1)
        #expect(instances[0].sessionId == session.id)
        #expect(instances[0].definitionId == GameType.licensePlate.rawValue)
        #expect(instances[0].ruleSet.gameDefinitionId == GameType.licensePlate.rawValue)
        #expect(instances[0].licensePlateConfig()?.selectedCountries == [.unitedStates, .canada])
    }

    @Test func defaultConfigReturnsLicensePlateOnly() async throws {
        let session = makeSession()
        let config = CombinedGameConfiguration.default

        let instances = CombinedGameAssembler.assemble(session: session, config: config)

        #expect(config.enabledGameTypes == [.licensePlate])
        #expect(instances.count == 1)
        #expect(instances[0].definitionId == "license_plate")
    }

    @Test func onlyAvailableTypesUsed() async throws {
        let session = makeSession()
        // MVP: roadSignBingo and carModelSpotting are not available
        let config = CombinedGameConfiguration(enabledGameTypes: [.licensePlate, .roadSignBingo, .carModelSpotting])

        let instances = CombinedGameAssembler.assemble(session: session, config: config)

        #expect(config.availableEnabledTypes.count == 1)
        #expect(instances.count == 1)
        #expect(instances[0].definitionId == GameType.licensePlate.rawValue)
    }

    @Test func noAvailableTypesReturnsEmpty() async throws {
        let session = makeSession()
        let config = CombinedGameConfiguration(enabledGameTypes: [.roadSignBingo, .carModelSpotting])

        let instances = CombinedGameAssembler.assemble(session: session, config: config)

        #expect(config.availableEnabledTypes.isEmpty)
        #expect(instances.isEmpty)
    }

    @Test @MainActor func emptyEnabledTypesReturnsEmpty() async throws {
        let session = makeSession()
        let config = CombinedGameConfiguration(enabledGameTypes: [])

        let instances = CombinedGameAssembler.assemble(session: session, config: config)

        #expect(instances.isEmpty)
    }

    @Test func eachInstanceHasUniqueId() async throws {
        let session = makeSession()
        let config = CombinedGameConfiguration(enabledGameTypes: [.licensePlate])

        let instances = CombinedGameAssembler.assemble(session: session, config: config)
        let instances2 = CombinedGameAssembler.assemble(session: session, config: config)

        #expect(instances.count == 1)
        #expect(instances2.count == 1)
        #expect(instances[0].id != instances2[0].id)
    }

    @Test func usesSessionStartedAtForInstanceStartedAt() async throws {
        let started = Date().addingTimeInterval(-3600)
        let session = makeSession(startedAt: started)

        let config = CombinedGameConfiguration(enabledGameTypes: [.licensePlate])
        let instances = CombinedGameAssembler.assemble(session: session, config: config)

        #expect(instances.count == 1)
        #expect(instances[0].startedAt == started)
    }

    @Test func licensePlateConfigOverloadNormalizesTerritoriesForCountrySet() async throws {
        let raw = LicensePlateTerritoryOptions(includeUSTerritories: true, includeCanadianTerritories: true, includeDC: true)
        let config = CombinedGameAssembler.licensePlateConfig(from: [.canada], territoryOptions: raw)
        #expect(config.selectedCountries == [.canada])
        #expect(config.territoryOptions.includeCanadianTerritories == true)
        #expect(config.territoryOptions.includeUSTerritories == false)
        #expect(config.territoryOptions.includeDC == false)
    }

    @Test func competitiveGameModeIsNotDerivedFromTripMode() async throws {
        let session = makeSession(mode: .multiplayer)
        let config = CombinedGameConfiguration(enabledGameTypes: [.licensePlate])
        let choices: [GameType: GameSetupChoice] = [
            .licensePlate: GameSetupChoice(gameType: .licensePlate, gameMode: .competitive, teams: [])
        ]
        let instances = CombinedGameAssembler.assemble(
            session: session,
            config: config,
            choicesByGameType: choices,
            licensePlateConfig: nil
        )
        #expect(instances.count == 1)
        #expect(instances[0].commonConfig.gameMode == .competitive)
    }

    @Test func teamsFromChoiceAppliedToInstance() async throws {
        let session = makeSession(mode: .solo)
        let teams = [TripTeam(name: "Team Alpha", participantUserIds: ["user1"])]
        let config = CombinedGameConfiguration(enabledGameTypes: [.licensePlate])
        let choices: [GameType: GameSetupChoice] = [
            .licensePlate: GameSetupChoice(gameType: .licensePlate, gameMode: .collaborative, teams: teams)
        ]
        let instances = CombinedGameAssembler.assemble(
            session: session,
            config: config,
            choicesByGameType: choices,
            licensePlateConfig: nil
        )
        #expect(instances.count == 1)
        #expect(instances[0].teams.count == 1)
        #expect(instances[0].teams[0].name == "Team Alpha")
    }
}
