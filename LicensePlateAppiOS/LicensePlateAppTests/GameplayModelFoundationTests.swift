//
//  GameplayModelFoundationTests.swift
//  LicensePlateAppTests
//
//  Step 01 — gameplay model foundation: participant creation, credit shapes, migration-safe defaults.
//

import Testing
import Foundation
@testable import LicensePlateApp


struct GameplayModelFoundationTests {

    @Test func tripModeDefaultsAndCases() async throws {
        #expect(TripMode.solo.rawValue == "solo")
        #expect(TripMode.collaborative.rawValue == "collaborative")
        #expect(TripMode.competitive.rawValue == "competitive")
        #expect(TripMode.combined.rawValue == "combined")
    }

    @Test func tripStatusDefaultsAndCases() async throws {
        #expect(TripStatus.draft.rawValue == "draft")
        #expect(TripStatus.active.rawValue == "active")
        #expect(TripStatus.ended.rawValue == "ended")
        #expect(TripStatus.cancelled.rawValue == "cancelled")
    }

    @Test func participantCreation() async throws {
        let p = await TripParticipant(userId: "user1", role: .owner, joinedAt: .now)
        #expect(p.userId == "user1")
        #expect(p.role == .owner)
        #expect(p.leftAt == nil)
    }

    @Test func collaborativeCreditShape() async throws {
        let credit = await GameCredit(
            discoveryId: "d1",
            participantId: "user1",
            creditType: .shared,
            weight: 0.5
        )
        #expect(credit.creditType == .shared)
        #expect(credit.weight == 0.5)
    }

    @Test func competitiveCreditShape() async throws {
        let credit = await GameCredit(
            discoveryId: "d1",
            participantId: "user1",
            creditType: .full,
            weight: 1.0
        )
        #expect(credit.creditType == .full)
        #expect(credit.weight == 1.0)
    }

    @Test func tripSessionMigrationSafeDefaults() async throws {
        let session = await TripSession(name: "Test Trip")
        #expect(session.status == .draft)
        #expect(session.mode == .solo)
        #expect(session.participants.isEmpty)
        #expect(session.legacyTripId == nil)
        #expect(session.enabledCountryRawValues.count >= 3)
    }

    @Test func gameInstanceAndDiscoveryConstruction() async throws {
        let ruleSet = await GameRuleSet(gameDefinitionId: "license_plate")
        let sessionId = UUID()
        let gameInstance = await GameInstance(
            definitionId: "license_plate",
            sessionId: sessionId,
            ruleSet: ruleSet
        )
        #expect(gameInstance.definitionId == "license_plate")
        #expect(gameInstance.sessionId == sessionId)

        let discovery = await GameDiscovery(
            gameInstanceId: gameInstance.id,
            participantId: "user1",
            targetId: "us-ca",
            inputMethod: .list
        )
        #expect(discovery.targetId == "us-ca")
        #expect(discovery.participantId == "user1")
    }

    @Test func gameDefinitionExtensible() async throws {
        let def = await GameDefinition(id: "custom_game", name: "Custom", description: "A custom game")
        #expect(def.id == "custom_game")
        #expect(def.name == "Custom")
    }

    @Test func travelLogEntryConstruction() async throws {
        let sessionId = UUID()
        let entry = await TravelLogEntry(
            sessionId: sessionId,
            tripName: "Road Trip",
            endedAt: .now,
            summary: "12 regions found"
        )
        #expect(entry.tripName == "Road Trip")
        #expect(entry.summary == "12 regions found")
    }

    @Test func tripSessionMapperToLegacyDTO() async throws {
        let session = TripSession(name: "Mapped Trip", status: .ended)
        let discoveries = [
            GameDiscovery(
                gameInstanceId: UUID(),
                participantId: "user1",
                targetId: "us-ca",
                inputMethod: .list
            )
        ]
        let dto = await TripSessionMapper.toLegacyDTO(session: session, discoveries: discoveries)
        #expect(dto.name == "Mapped Trip")
        #expect(dto.id == session.id)
        #expect(dto.isTripEnded == true)
        #expect(dto.foundRegions.count == 1)
        await #expect(dto.foundRegions[0].regionID == "us-ca")
        await #expect(dto.foundRegions[0].foundBy == "user1")
    }

    // Step 06.5.5 — TripSessionMapper collapseByTargetId for collaborative display
    @Test func tripSessionMapperCollapseByTargetIdOneFoundRegionPerTargetWithFirstFinder() async throws {
        let session = TripSession(name: "Collapsed", status: .active)
        let gameId = UUID()
        let base = Date()
        let discoveries = [
            GameDiscovery(
                gameInstanceId: gameId,
                participantId: "user2",
                targetId: "us-ca",
                discoveredAt: base.addingTimeInterval(10),
                inputMethod: .voice
            ),
            GameDiscovery(
                gameInstanceId: gameId,
                participantId: "user1",
                targetId: "us-ca",
                discoveredAt: base,
                inputMethod: .list
            )
        ]
        let dto = TripSessionMapper.toLegacyDTO(session: session, discoveries: discoveries, collapseByTargetId: true)
        #expect(dto.foundRegions.count == 1)
        #expect(dto.foundRegions[0].regionID == "us-ca")
        #expect(dto.foundRegions[0].foundBy == "user1")
    }
}
