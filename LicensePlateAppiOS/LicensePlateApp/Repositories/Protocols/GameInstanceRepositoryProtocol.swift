//
//  GameInstanceRepositoryProtocol.swift
//  LicensePlateApp
//
//  Protocol for game instance persistence. Enables test doubles. Step 03 — repository layer.
//

import Foundation
import SwiftData

@MainActor
protocol GameInstanceRepositoryProtocol: AnyObject {
    func setModelContext(_ context: ModelContext)

    func create(instance: GameInstance) throws
    func fetchByTripSession(sessionId: UUID) throws -> [GameInstance]
    func updateRuleSet(instanceId: UUID, ruleSet: GameRuleSet) throws
    func saveScoreSnapshot(instanceId: UUID, snapshot: Data) throws
    func instance(byId id: UUID) throws -> GameInstance?
}
