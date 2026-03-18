//
//  GameInstanceRepositoryProtocol.swift
//  LicensePlateApp
//
//  Protocol for game instance persistence. Enables test doubles. Step 03 — repository layer.
//  Single source for per-game data. "Primary" game for a session is chosen by callers
//  (e.g. ActiveTripsListViewModel / TripRollup), not by the repository.
//

import Foundation
import SwiftData

@MainActor
protocol GameInstanceRepositoryProtocol: AnyObject {
    func setModelContext(_ context: ModelContext)

    func create(instance: GameInstance) throws
    func fetchByTripSession(sessionId: UUID) throws -> [GameInstance]
    /// Returns the number of game instances for the session (e.g. for Travel Log projection).
    func gameCount(sessionId: UUID) throws -> Int
    /// Removes all game instances for the session; call from lifecycle when a session is deleted/cancelled (detach).
    func deleteForSession(sessionId: UUID) throws
    func update(instance: GameInstance) throws
    /// Step 07.5 — Transition all games for the session to started and lock config.
    func transitionGamesToStarted(sessionId: UUID) throws
    func updateRuleSet(instanceId: UUID, ruleSet: GameRuleSet) throws
    func saveScoreSnapshot(instanceId: UUID, snapshot: Data) throws
    func instance(byId id: UUID) throws -> GameInstance?
}
