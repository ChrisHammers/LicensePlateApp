//
//  GameModeRulesEngineTests.swift
//  LicensePlateAppTests
//
//  Step 6.9.1 — GameModeRulesEngine: canParticipantUnfind, creditType, displayFirstFinderProminently (GameMode only).
//

import Foundation
import Testing
@testable import LicensePlateApp

struct GameModeRulesEngineTests {

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
        #expect(GameModeRulesEngine.creditType(for: .collaborative) == .shared)
    }

    @Test func creditTypeCompetitiveIsFull() async throws {
        #expect(GameModeRulesEngine.creditType(for: .competitive) == .full)
    }

    // MARK: - displayFirstFinderProminently

    @Test func displayFirstFinderProminentlyCompetitiveIsTrue() async throws {
        #expect(GameModeRulesEngine.displayFirstFinderProminently(mode: .competitive) == true)
    }

    @Test func displayFirstFinderProminentlyCollaborativeIsFalse() async throws {
        #expect(GameModeRulesEngine.displayFirstFinderProminently(mode: .collaborative) == false)
    }

    // MARK: - canParticipantUnfind

    @Test func canParticipantUnfindCollaborativeAnyFinderCanUnfind() async throws {
        let d1 = makeDiscovery(participantId: "user1")
        let d2 = makeDiscovery(participantId: "user2")
        let all = [d1, d2]
        #expect(GameModeRulesEngine.canParticipantUnfind(mode: .collaborative, participantId: "user1", discovery: d1, allDiscoveriesForTarget: all) == true)
        #expect(GameModeRulesEngine.canParticipantUnfind(mode: .collaborative, participantId: "user2", discovery: d1, allDiscoveriesForTarget: all) == true)
        #expect(GameModeRulesEngine.canParticipantUnfind(mode: .collaborative, participantId: "user1", discovery: d2, allDiscoveriesForTarget: all) == true)
        #expect(GameModeRulesEngine.canParticipantUnfind(mode: .collaborative, participantId: "user2", discovery: d2, allDiscoveriesForTarget: all) == true)
    }

    @Test func canParticipantUnfindCollaborativeNonFinderCannotUnfind() async throws {
        let d1 = makeDiscovery(participantId: "user1")
        let result = GameModeRulesEngine.canParticipantUnfind(
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
        #expect(GameModeRulesEngine.canParticipantUnfind(mode: .competitive, participantId: "user1", discovery: d1, allDiscoveriesForTarget: all) == true)
        #expect(GameModeRulesEngine.canParticipantUnfind(mode: .competitive, participantId: "user2", discovery: d2, allDiscoveriesForTarget: all) == true)
        #expect(GameModeRulesEngine.canParticipantUnfind(mode: .competitive, participantId: "user2", discovery: d1, allDiscoveriesForTarget: all) == false)
        #expect(GameModeRulesEngine.canParticipantUnfind(mode: .competitive, participantId: "user1", discovery: d2, allDiscoveriesForTarget: all) == false)
    }

    @Test func canParticipantUnfindCompetitiveDiscovererWithEmptyListCanUnfind() async throws {
        let discovery = makeDiscovery(participantId: "user1")
        let result = GameModeRulesEngine.canParticipantUnfind(
            mode: .competitive,
            participantId: "user1",
            discovery: discovery,
            allDiscoveriesForTarget: []
        )
        #expect(result == true)
    }
}
