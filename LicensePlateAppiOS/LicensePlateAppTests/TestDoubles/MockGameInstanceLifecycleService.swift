//
//  MockGameInstanceLifecycleService.swift
//  LicensePlateAppTests
//
//  Test double for GameInstanceLifecycleServiceProtocol.
//

import Foundation
@testable import LicensePlateApp

@MainActor
final class MockGameInstanceLifecycleService: GameInstanceLifecycleServiceProtocol {
    var startGameCallCount = 0
    var endGameCallCount = 0
    var resetGameCallCount = 0
    var lastResetSessionId: UUID?
    var lastResetGameInstanceId: UUID?
    var shouldThrow = false

    func startGame(sessionId: UUID, gameInstanceId: UUID) throws {
        if shouldThrow { throw NSError(domain: "MockGameInstanceLifecycleService", code: -1, userInfo: nil) }
        startGameCallCount += 1
    }

    func endGame(sessionId: UUID, gameInstanceId: UUID) throws {
        if shouldThrow { throw NSError(domain: "MockGameInstanceLifecycleService", code: -1, userInfo: nil) }
        endGameCallCount += 1
    }

    func resetGame(sessionId: UUID, gameInstanceId: UUID) throws {
        if shouldThrow { throw NSError(domain: "MockGameInstanceLifecycleService", code: -1, userInfo: nil) }
        resetGameCallCount += 1
        lastResetSessionId = sessionId
        lastResetGameInstanceId = gameInstanceId
    }
}
