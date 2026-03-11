//
//  TripModeRulesEngineTests.swift
//  LicensePlateAppTests
//
//  Step 05 — TripModeRulesEngine: canParticipantUnfind, creditType, displayFirstFinderProminently.
//

import Foundation
import Testing
@testable import LicensePlateApp

struct TripModeRulesEngineTests {

    private func makeDiscovery(
        participantId: String,
        targetId: String = "region-1",
        gameInstanceId: UUID = UUID(),
        discoveredAt: Date = Date()
    ) -> GameDiscovery {
        GameDiscovery(
            gameInstanceId: gameInstanceId,
            participantId: participantId,
            targetId: targetId,
            discoveredAt: discoveredAt,
            inputMethod: .list
        )
    }

    // MARK: - creditType

    @Test func creditTypeCollaborativeIsShared() async throws {
        #expect(TripModeRulesEngine.creditType(for: .collaborative) == .shared)
    }

    @Test func creditTypeSoloIsFull() async throws {
        #expect(TripModeRulesEngine.creditType(for: .solo) == .full)
    }

    @Test func creditTypeCompetitiveIsFull() async throws {
        #expect(TripModeRulesEngine.creditType(for: .competitive) == .full)
    }

    @Test func creditTypeCombinedIsFull() async throws {
        #expect(TripModeRulesEngine.creditType(for: .combined) == .full)
    }

    // MARK: - displayFirstFinderProminently

    @Test func displayFirstFinderProminentlyCompetitiveIsTrue() async throws {
        #expect(TripModeRulesEngine.displayFirstFinderProminently(mode: .competitive) == true)
    }

    @Test func displayFirstFinderProminentlyCollaborativeIsFalse() async throws {
        #expect(TripModeRulesEngine.displayFirstFinderProminently(mode: .collaborative) == false)
    }

    @Test func displayFirstFinderProminentlySoloIsFalse() async throws {
        #expect(TripModeRulesEngine.displayFirstFinderProminently(mode: .solo) == false)
    }

    @Test func displayFirstFinderProminentlyCombinedIsFalse() async throws {
        #expect(TripModeRulesEngine.displayFirstFinderProminently(mode: .combined) == false)
    }

    // MARK: - canParticipantUnfind

    @Test func canParticipantUnfindSoloDiscovererCanUnfind() async throws {
        let discovery = makeDiscovery(participantId: "user1")
        let result = TripModeRulesEngine.canParticipantUnfind(
            mode: .solo,
            participantId: "user1",
            discovery: discovery,
            allDiscoveriesForTarget: [discovery]
        )
        #expect(result == true)
    }

    @Test func canParticipantUnfindSoloOtherCannotUnfind() async throws {
        let discovery = makeDiscovery(participantId: "user1")
        let result = TripModeRulesEngine.canParticipantUnfind(
            mode: .solo,
            participantId: "user2",
            discovery: discovery,
            allDiscoveriesForTarget: [discovery]
        )
        #expect(result == false)
    }

    @Test func canParticipantUnfindCollaborativeAnyFinderCanUnfind() async throws {
        let d1 = makeDiscovery(participantId: "user1")
        let d2 = makeDiscovery(participantId: "user2")
        let all = [d1, d2]
        #expect(TripModeRulesEngine.canParticipantUnfind(mode: .collaborative, participantId: "user1", discovery: d1, allDiscoveriesForTarget: all) == true)
        #expect(TripModeRulesEngine.canParticipantUnfind(mode: .collaborative, participantId: "user2", discovery: d1, allDiscoveriesForTarget: all) == true)
        #expect(TripModeRulesEngine.canParticipantUnfind(mode: .collaborative, participantId: "user1", discovery: d2, allDiscoveriesForTarget: all) == true)
        #expect(TripModeRulesEngine.canParticipantUnfind(mode: .collaborative, participantId: "user2", discovery: d2, allDiscoveriesForTarget: all) == true)
    }

    @Test func canParticipantUnfindCollaborativeNonFinderCannotUnfind() async throws {
        let d1 = makeDiscovery(participantId: "user1")
        let result = TripModeRulesEngine.canParticipantUnfind(
            mode: .collaborative,
            participantId: "user2",
            discovery: d1,
            allDiscoveriesForTarget: [d1]
        )
        #expect(result == false)
    }

    @Test func canParticipantUnfindCompetitiveOnlyDiscovererCanUnfind() async throws {
        let d1 = makeDiscovery(participantId: "user1")
        let d2 = makeDiscovery(participantId: "user2")
        let all = [d1, d2]
        #expect(TripModeRulesEngine.canParticipantUnfind(mode: .competitive, participantId: "user1", discovery: d1, allDiscoveriesForTarget: all) == true)
        #expect(TripModeRulesEngine.canParticipantUnfind(mode: .competitive, participantId: "user2", discovery: d2, allDiscoveriesForTarget: all) == true)
        #expect(TripModeRulesEngine.canParticipantUnfind(mode: .competitive, participantId: "user2", discovery: d1, allDiscoveriesForTarget: all) == false)
        #expect(TripModeRulesEngine.canParticipantUnfind(mode: .competitive, participantId: "user1", discovery: d2, allDiscoveriesForTarget: all) == false)
    }

    @Test func canParticipantUnfindCombinedAnyFinderCanUnfind() async throws {
        let d1 = makeDiscovery(participantId: "user1")
        let d2 = makeDiscovery(participantId: "user2")
        let all = [d1, d2]
        #expect(TripModeRulesEngine.canParticipantUnfind(mode: .combined, participantId: "user1", discovery: d1, allDiscoveriesForTarget: all) == true)
        #expect(TripModeRulesEngine.canParticipantUnfind(mode: .combined, participantId: "user2", discovery: d1, allDiscoveriesForTarget: all) == true)
    }

    @Test func canParticipantUnfindEmptyDiscoveriesSoloDiscovererCanUnfind() async throws {
        let discovery = makeDiscovery(participantId: "user1")
        let result = TripModeRulesEngine.canParticipantUnfind(
            mode: .solo,
            participantId: "user1",
            discovery: discovery,
            allDiscoveriesForTarget: []
        )
        #expect(result == true)
    }
}
