//
//  GameInstanceConfigEnvelopeTests.swift
//  LicensePlateAppTests
//
//  Step 07.5 — Round-trip GameInstance with commonConfig and license_plate payload; legacy defaulting.
//

import Foundation
import SwiftData
import Testing
@testable import LicensePlateApp

@MainActor
struct GameInstanceConfigEnvelopeTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: [config])
    }

    @Test func roundTripWithCommonConfigAndLicensePlatePayload() async throws {
        let sessionId = UUID()
        let lpConfig = LicensePlateGameConfig(
            selectedCountriesRawValues: [PlateRegion.Country.unitedStates.rawValue],
            territoryOptions: LicensePlateTerritoryOptions(includeUSTerritories: false, includeCanadianTerritories: true, includeDC: true)
        )
        let payloadData = try JSONEncoder().encode(lpConfig)
        let commonConfig = CommonGameConfig(
            lifecycleState: .created,
            gameMode: .competitive,
            scoringProfile: "default",
            configLocked: false,
            configLockReason: .none
        )
        let instance = GameInstance(
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: GameType.licensePlate.rawValue),
            commonConfig: commonConfig,
            gameSpecificPayloadType: GameType.licensePlate.rawValue,
            gameSpecificPayloadVersion: "1",
            gameSpecificPayloadData: payloadData
        )

        let entity = GameInstanceMapper.toEntity(instance)
        #expect(entity.commonConfigData != nil)
        #expect(entity.gameSpecificPayloadType == GameType.licensePlate.rawValue)
        #expect(entity.gameSpecificPayloadData != nil)

        let back = GameInstanceMapper.toDomain(entity)
        #expect(back.commonConfig.gameMode == GameMode.competitive)
        #expect(back.commonConfig.lifecycleState == GameInstanceState.created)
        let decoded = back.licensePlateConfig()
        #expect(decoded != nil)
        #expect(decoded?.selectedCountries == [.unitedStates])
        #expect(decoded?.territoryOptions.includeDC == true)
        #expect(decoded?.territoryOptions.includeUSTerritories == false)
        #expect(decoded?.territoryOptions.includeCanadianTerritories == true)
    }

    @Test func legacyEntityWithoutCommonConfigDataDecodesWithDefaults() async throws {
        let entity = GameInstanceEntity(
            id: UUID().uuidString,
            definitionId: "license_plate",
            sessionId: UUID().uuidString,
            startedAt: Date(),
            endedAt: nil,
            ruleSetData: try? JSONEncoder().encode(GameRuleSet(gameDefinitionId: "license_plate")),
            commonConfigData: nil,
            gameSpecificPayloadType: nil,
            gameSpecificPayloadVersion: nil,
            gameSpecificPayloadData: nil
        )

        let domain = GameInstanceMapper.toDomain(entity)
        #expect(domain.commonConfig.lifecycleState == .created)
        #expect(domain.commonConfig.configLockReason == .none)
        #expect(domain.commonConfig.scoringProfile == "default")
        #expect(domain.licensePlateConfig() == nil)
    }

    @Test func createdGamesFromAssemblerHaveDefaultScoringProfile() async throws {
        let session = TripSession(
            id: UUID(),
            name: "Test",
            status: .active,
            mode: .solo,
            createdAt: .now,
            participants: [TripParticipant(userId: "u1", role: .owner)]
        )
        let config = CombinedGameConfiguration(enabledGameTypes: [.licensePlate])
        let lpConfig = CombinedGameAssembler.licensePlateConfig(from: [.unitedStates, .canada, .mexico])
        let instances = CombinedGameAssembler.assemble(session: session, config: config, licensePlateConfig: lpConfig)
        #expect(instances.count == 1)
        #expect(instances[0].commonConfig.scoringProfile == "default")
        #expect(instances[0].commonConfig.lifecycleState == .created)
        #expect(instances[0].licensePlateConfig() != nil)
    }
}
