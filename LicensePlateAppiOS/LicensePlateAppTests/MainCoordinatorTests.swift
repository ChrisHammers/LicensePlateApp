//
//  MainCoordinatorTests.swift
//  LicensePlateAppTests
//
//  Step 6.8 — MainCoordinator: path updates for openSession, openGame, pop, popToRoot.
//

import Foundation
import Testing
@testable import LicensePlateApp

@MainActor
struct MainCoordinatorTests {

    @Test func openSessionAppendsSessionRoute() async throws {
        let coordinator = MainCoordinator()
        let sessionId = UUID()

        #expect(coordinator.path.isEmpty)

        coordinator.openSession(sessionId)

        #expect(coordinator.path.count == 1)
        if case .session(let id) = coordinator.path[0] {
            #expect(id == sessionId)
        } else {
            Issue.record("Expected .session(\(sessionId)), got \(coordinator.path[0])")
        }
    }

    @Test func openGameAppendsGameRoute() async throws {
        let coordinator = MainCoordinator()
        let sessionId = UUID()
        let gameId = UUID()

        #expect(coordinator.path.isEmpty)

        coordinator.openGame(sessionId: sessionId, gameId: gameId)

        #expect(coordinator.path.count == 1)
        if case .game(let sid, let gid) = coordinator.path[0] {
            #expect(sid == sessionId)
            #expect(gid == gameId)
        } else {
            Issue.record("Expected .game(\(sessionId), \(gameId)), got \(coordinator.path[0])")
        }
    }

    @Test func popRemovesLastRoute() async throws {
        let coordinator = MainCoordinator()
        let sessionId = UUID()
        coordinator.openSession(sessionId)
        coordinator.openSession(UUID())
        #expect(coordinator.path.count == 2)

        coordinator.pop()
        #expect(coordinator.path.count == 1)
        if case .session(let id) = coordinator.path[0] {
            #expect(id == sessionId)
        }

        coordinator.pop()
        #expect(coordinator.path.isEmpty)
    }

    @Test func popWhenEmptyDoesNotCrash() async throws {
        let coordinator = MainCoordinator()
        coordinator.pop()
        #expect(coordinator.path.isEmpty)
    }

    @Test func popToRootClearsPath() async throws {
        let coordinator = MainCoordinator()
        coordinator.openSession(UUID())
        coordinator.openGame(sessionId: UUID(), gameId: UUID())
        #expect(coordinator.path.count == 2)

        coordinator.popToRoot()
        #expect(coordinator.path.isEmpty)
    }

    @Test func completeTripEndFlowClearsPathAndSetsPendingSummary() async throws {
        let coordinator = MainCoordinator()
        let sessionId = UUID()
        coordinator.openSession(UUID())
        coordinator.openGame(sessionId: sessionId, gameId: UUID())
        #expect(coordinator.path.count == 2)

        coordinator.completeTripEndFlow(sessionId: sessionId)

        #expect(coordinator.path.isEmpty)
        #expect(coordinator.pendingPostEndSummarySessionId == sessionId)
    }

    @Test func clearPendingPostEndSummaryClearsId() async throws {
        let coordinator = MainCoordinator()
        let sessionId = UUID()
        coordinator.completeTripEndFlow(sessionId: sessionId)
        coordinator.clearPendingPostEndSummary()
        #expect(coordinator.pendingPostEndSummarySessionId == nil)
    }
}
