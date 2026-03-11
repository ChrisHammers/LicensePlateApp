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
        status: TripStatus = .draft,
        mode: TripMode = .solo,
        startedAt: Date? = nil,
        endedAt: Date? = nil
    ) -> TripSession {
        TripSession(
            id: id,
            name: name,
            status: status,
            mode: mode,
            createdBy: "user1",
            startedAt: startedAt ?? Date(),
            endedAt: endedAt,
            participants: [TripParticipant(userId: "user1", role: .owner)],
            enabledCountryRawValues: ["United States", "Canada", "Mexico"]
        )
    }

    @Test func oneGameTypeReturnsOneInstance() async throws {
        let session = makeSession()
        let config = CombinedGameConfiguration(enabledGameTypes: [.licensePlate])

        let instances = CombinedGameAssembler.assemble(session: session, config: config)

        #expect(instances.count == 1)
        #expect(instances[0].sessionId == session.id)
        #expect(instances[0].definitionId == GameType.licensePlate.rawValue)
        #expect(instances[0].ruleSet.gameDefinitionId == GameType.licensePlate.rawValue)
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

    @Test func emptyEnabledTypesReturnsEmpty() async throws {
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
}
