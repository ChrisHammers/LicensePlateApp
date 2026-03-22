//
//  SelectedGameConfigReadPathTests.swift
//  LicensePlateAppTests
//
//  Step 6.9.2 — Read path for "enabled countries" uses selected GameInstance config, not TripSession.
//

import Foundation
import Testing
@testable import LicensePlateApp

struct SelectedGameConfigReadPathTests {

    @Test func enabledCountriesForDisplayComeFromGamePayload() async throws {
        let session = TripSession(
            id: UUID(),
            name: "Trip",
            status: .active,
            createdAt: Date(),
            participants: []
        )
        let usOnlyConfig = LicensePlateGameConfig(selectedCountriesRawValues: [PlateRegion.Country.unitedStates.rawValue], territoryOptions: LicensePlateTerritoryOptions())
        let payloadData = try JSONEncoder().encode(usOnlyConfig)
        let game = GameInstance(
            definitionId: GameType.licensePlate.rawValue,
            sessionId: session.id,
            ruleSet: GameRuleSet(gameDefinitionId: GameType.licensePlate.rawValue),
            gameSpecificPayloadData: payloadData
        )
        let config = game.licensePlateConfig() ?? LicensePlateGameConfig(selectedCountriesRawValues: [PlateRegion.Country.unitedStates.rawValue, PlateRegion.Country.canada.rawValue, PlateRegion.Country.mexico.rawValue], territoryOptions: LicensePlateTerritoryOptions())
        let targetIds = Set(LicensePlateScopeCalculator.targetRegionIds(for: config))
        let countries = Array(Set(PlateRegion.all.filter { targetIds.contains($0.id) }.map(\.country)))
        #expect(countries.contains(.unitedStates))
        #expect(countries.count >= 1)
    }

    @Test func assemblerUsesPassedLicensePlateConfigNotSession() async throws {
        let session = TripSession(
            id: UUID(),
            name: "Trip",
            status: .active,
            createdAt: Date(),
            participants: [TripParticipant(userId: "u1", role: .owner, joinedAt: Date())]
        )
        let mexicoOnlyConfig = CombinedGameAssembler.licensePlateConfig(from: [.mexico])
        #expect(mexicoOnlyConfig.selectedCountries == [.mexico])
        let config = CombinedGameConfiguration(enabledGameTypes: [.licensePlate])
        let instances = CombinedGameAssembler.assemble(session: session, config: config, licensePlateConfig: mexicoOnlyConfig)
        #expect(instances.count == 1)
        let decoded = instances[0].licensePlateConfig()
        #expect(decoded?.selectedCountries == [.mexico])
    }

    @Test func readPathUsesTerritoryOffForUSWhenDCExcluded() async throws {
        let session = TripSession(
            id: UUID(),
            name: "Trip",
            status: .active,
            createdAt: Date(),
            participants: []
        )
        let cfg = CombinedGameAssembler.licensePlateConfig(
            from: [.unitedStates],
            territoryOptions: LicensePlateTerritoryOptions(includeUSTerritories: false, includeCanadianTerritories: false, includeDC: false)
        )
        let data = try JSONEncoder().encode(cfg)
        let game = GameInstance(
            definitionId: GameType.licensePlate.rawValue,
            sessionId: session.id,
            ruleSet: GameRuleSet(gameDefinitionId: GameType.licensePlate.rawValue),
            gameSpecificPayloadData: data
        )
        let decoded = game.licensePlateConfig()!
        let ids = LicensePlateScopeCalculator.targetRegionIds(for: decoded)
        #expect(ids.contains("us-dc") == false)
        #expect(ids.count == 50)
    }
}
