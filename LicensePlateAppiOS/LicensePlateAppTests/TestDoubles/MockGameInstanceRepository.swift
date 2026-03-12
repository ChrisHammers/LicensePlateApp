//
//  MockGameInstanceRepository.swift
//  LicensePlateAppTests
//
//  Step 13 — Test double for GameInstanceRepositoryProtocol. In-memory store; configurable errors.
//

import Foundation
import SwiftData
@testable import LicensePlateApp

@MainActor
final class MockGameInstanceRepository: GameInstanceRepositoryProtocol {
    private var instances: [UUID: GameInstance] = [:]
    private var bySession: [UUID: [GameInstance]] = [:]
    private var context: ModelContext?
    var shouldThrow = false

    func setModelContext(_ context: ModelContext) {
        self.context = context
    }

    func create(instance: GameInstance) throws {
        if shouldThrow { throw NSError(domain: "MockGameInstanceRepository", code: -1, userInfo: nil) }
        instances[instance.id] = instance
        var list = bySession[instance.sessionId] ?? []
        list.append(instance)
        bySession[instance.sessionId] = list
    }

    func fetchByTripSession(sessionId: UUID) throws -> [GameInstance] {
        if shouldThrow { throw NSError(domain: "MockGameInstanceRepository", code: -1, userInfo: nil) }
        return bySession[sessionId] ?? []
    }

    func update(instance: GameInstance) throws {
        if shouldThrow { throw NSError(domain: "MockGameInstanceRepository", code: -1, userInfo: nil) }
        instances[instance.id] = instance
        if var list = bySession[instance.sessionId] {
            list.removeAll { $0.id == instance.id }
            list.append(instance)
            bySession[instance.sessionId] = list
        }
    }

    func transitionGamesToStarted(sessionId: UUID) throws {
        if shouldThrow { throw NSError(domain: "MockGameInstanceRepository", code: -1, userInfo: nil) }
        let idsToUpdate = instances.filter { $0.value.sessionId == sessionId }.map(\.key)
        for id in idsToUpdate {
            guard var inst = instances[id] else { continue }
            inst.commonConfig.lifecycleState = .started
            inst.commonConfig.configLocked = true
            inst.commonConfig.configLockReason = .gameStarted
            instances[id] = inst
        }
        if var list = bySession[sessionId] {
            for i in list.indices {
                list[i].commonConfig.lifecycleState = .started
                list[i].commonConfig.configLocked = true
                list[i].commonConfig.configLockReason = .gameStarted
            }
            bySession[sessionId] = list
        }
    }

    func updateRuleSet(instanceId: UUID, ruleSet: GameRuleSet) throws {
        if shouldThrow { throw NSError(domain: "MockGameInstanceRepository", code: -1, userInfo: nil) }
        if var inst = instances[instanceId] {
            inst.ruleSet = ruleSet
            instances[instanceId] = inst
        }
    }

    func saveScoreSnapshot(instanceId: UUID, snapshot: Data) throws {
        if shouldThrow { throw NSError(domain: "MockGameInstanceRepository", code: -1, userInfo: nil) }
        // No-op for mock; could store if tests need it
    }

    func instance(byId id: UUID) throws -> GameInstance? {
        if shouldThrow { throw NSError(domain: "MockGameInstanceRepository", code: -1, userInfo: nil) }
        return instances[id]
    }

    /// Test helper: seed instances
    func seed(_ instance: GameInstance) {
        instances[instance.id] = instance
        var list = bySession[instance.sessionId] ?? []
        list.removeAll { $0.id == instance.id }
        list.append(instance)
        bySession[instance.sessionId] = list
    }

    func clear() {
        instances.removeAll()
        bySession.removeAll()
    }
}
