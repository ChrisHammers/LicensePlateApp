//
//  TripActivityEventRepository.swift
//  LicensePlateApp
//
//  Step 01 — Append-only persistence for TripActivityEvent; derives discoveries/foundRegions by replaying region_found/region_removed.
//

import Foundation
import SwiftData
import Combine

protocol TripActivityEventRepositoryProtocol: AnyObject {
    func setModelContext(_ context: ModelContext)
    func append(_ event: TripActivityEvent) throws
    /// Inserts the event if no row exists with the same `id`. Returns `true` if inserted. If a row exists with the same `id`, returns `false` when session, kind, actor, and payload match; otherwise throws `idCollision`.
    @discardableResult
    func appendIfAbsent(_ event: TripActivityEvent) throws -> Bool
    /// Remote canonical import (bootstrap, supersede materialization): insert or merge when `id` exists with same session and kind.
    func importEventsIfAbsent(_ events: [TripActivityEvent]) throws
    /// Single-event variant of `importEventsIfAbsent` (e.g. Firestore activity_events listener).
    @discardableResult
    func reconcileRemoteActivityEvent(_ event: TripActivityEvent) throws -> Bool
    func event(byId id: String) throws -> TripActivityEvent?
    func events(sessionId: UUID, limit: Int?) throws -> [TripActivityEvent]
    func discoveries(sessionId: UUID, gameInstanceId: UUID?) throws -> [GameDiscovery]
    func foundRegions(sessionId: UUID, gameInstanceId: UUID?) throws -> [FoundRegion]
    /// Remove all events for a session (or discovery-related events for one game when gameInstanceId is provided). Used for reset game / cancel session cleanup.
    /// Physical delete is intentional for local reset/cancel UX; a future step may replace this with tombstones and remote reconciliation.
    func deleteEvents(sessionId: UUID, gameInstanceId: UUID?) throws
    /// Remove every persisted event whose payload references this game (e.g. game_started, discoveries). Used when removing a game instance from a trip.
    /// Physical delete is intentional for local UX; future tombstone/reconciliation may supersede.
    func deleteAllEventsForGame(sessionId: UUID, gameInstanceId: UUID) throws
    /// Single-event delete (e.g. server superseded a local `region_found` after sync). Step 13 fairness path.
    func deleteEvent(id: String) throws
}

@MainActor
final class TripActivityEventRepository: ObservableObject, TripActivityEventRepositoryProtocol {

    static let shared = TripActivityEventRepository()

    private var modelContext: ModelContext?

    private init() {}

    func setModelContext(_ context: ModelContext) {
        modelContext = context
    }

    func append(_ event: TripActivityEvent) throws {
        guard let ctx = modelContext else { throw TripActivityEventRepositoryError.noModelContext }
        #if DEBUG
        if DebugPersistenceFlags.shouldForceFailure(for: .append) {
            throw DebugForcedPersistenceError.append
        }
        #endif
        let payloadData = event.payload.flatMap { try? JSONEncoder().encode($0) }
        let entity = TripActivityEventEntity(
            id: event.id,
            sessionId: event.sessionId.uuidString,
            kind: event.kind.rawValue,
            timestamp: event.timestamp,
            actorId: event.actorId,
            payloadData: payloadData
        )
        ctx.insert(entity)
        try ctx.save()
    }

    @discardableResult
    func appendIfAbsent(_ event: TripActivityEvent) throws -> Bool {
        guard let ctx = modelContext else { throw TripActivityEventRepositoryError.noModelContext }
        if let existingEntity = try Self.fetchEntity(id: event.id, context: ctx) {
            let existing = entityToEvent(existingEntity)
            guard existing.sessionId == event.sessionId,
                  existing.kind == event.kind,
                  existing.actorId == event.actorId,
                  Self.payloadsEqual(existing.payload, event.payload) else {
                throw TripActivityEventRepositoryError.idCollision(id: event.id)
            }
            return false
        }
        #if DEBUG
        if DebugPersistenceFlags.shouldForceFailure(for: .append) {
            throw DebugForcedPersistenceError.append
        }
        #endif
        let payloadData = event.payload.flatMap { try? JSONEncoder().encode($0) }
        let entity = TripActivityEventEntity(
            id: event.id,
            sessionId: event.sessionId.uuidString,
            kind: event.kind.rawValue,
            timestamp: event.timestamp,
            actorId: event.actorId,
            payloadData: payloadData
        )
        ctx.insert(entity)
        try ctx.save()
        return true
    }

    func importEventsIfAbsent(_ events: [TripActivityEvent]) throws {
        for event in events {
            _ = try reconcileRemoteActivityEvent(event)
        }
    }

    @discardableResult
    func reconcileRemoteActivityEvent(_ event: TripActivityEvent) throws -> Bool {
        guard let ctx = modelContext else { throw TripActivityEventRepositoryError.noModelContext }
        if let existingEntity = try Self.fetchEntity(id: event.id, context: ctx) {
            let existing = entityToEvent(existingEntity)
            guard existing.sessionId == event.sessionId, existing.kind == event.kind else {
                throw TripActivityEventRepositoryError.idCollision(id: event.id)
            }
            let payloadData = event.payload.flatMap { try? JSONEncoder().encode($0) }
            // Compare payload semantically: JSONEncoder key order for `[String: String]` is not stable across decode/round-trips, so raw `Data` equality can falsely claim a merge is still needed.
            if Self.timestampsEffectivelyEqual(existingEntity.timestamp, event.timestamp),
               existingEntity.actorId == event.actorId,
               Self.payloadsEqual(existing.payload, event.payload) {
                return false
            }
            existingEntity.timestamp = event.timestamp
            existingEntity.actorId = event.actorId
            existingEntity.payloadData = payloadData
            try ctx.save()
            return true
        }
        #if DEBUG
        if DebugPersistenceFlags.shouldForceFailure(for: .append) {
            throw DebugForcedPersistenceError.append
        }
        #endif
        let payloadData = event.payload.flatMap { try? JSONEncoder().encode($0) }
        let entity = TripActivityEventEntity(
            id: event.id,
            sessionId: event.sessionId.uuidString,
            kind: event.kind.rawValue,
            timestamp: event.timestamp,
            actorId: event.actorId,
            payloadData: payloadData
        )
        ctx.insert(entity)
        try ctx.save()
        return true
    }

    func event(byId id: String) throws -> TripActivityEvent? {
        guard let ctx = modelContext else { throw TripActivityEventRepositoryError.noModelContext }
        guard let entity = try Self.fetchEntity(id: id, context: ctx) else { return nil }
        return entityToEvent(entity)
    }

    func events(sessionId: UUID, limit: Int?) throws -> [TripActivityEvent] {
        guard let ctx = modelContext else { throw TripActivityEventRepositoryError.noModelContext }
        let sid = sessionId.uuidString
        var descriptor = FetchDescriptor<TripActivityEventEntity>(
            predicate: #Predicate<TripActivityEventEntity> { $0.sessionId == sid }
        )
        descriptor.sortBy = [SortDescriptor(\.timestamp, order: .forward)]
        if let limit = limit {
            descriptor.fetchLimit = limit
        }
        let entities = try ctx.fetch(descriptor)
        return entities.map { entityToEvent($0) }
    }

    func discoveries(sessionId: UUID, gameInstanceId: UUID?) throws -> [GameDiscovery] {
        let allEvents = try events(sessionId: sessionId, limit: nil)
        return TripActivityEventDiscoveryReplay.replay(events: allEvents, gameInstanceFilter: gameInstanceId).discoveries
    }

    func foundRegions(sessionId: UUID, gameInstanceId: UUID?) throws -> [FoundRegion] {
        let allEvents = try events(sessionId: sessionId, limit: nil)
        return TripActivityEventDiscoveryReplay.replay(events: allEvents, gameInstanceFilter: gameInstanceId).foundRegions
    }

    func deleteEvents(sessionId: UUID, gameInstanceId: UUID?) throws {
        guard let ctx = modelContext else { throw TripActivityEventRepositoryError.noModelContext }
        let sid = sessionId.uuidString
        if let gid = gameInstanceId {
            let gidStr = gid.uuidString
            var descriptor = FetchDescriptor<TripActivityEventEntity>(
                predicate: #Predicate<TripActivityEventEntity> { $0.sessionId == sid }
            )
            let entities = try ctx.fetch(descriptor)
            for entity in entities where entity.kind == TripActivityEventKind.regionFound.rawValue || entity.kind == TripActivityEventKind.regionRemoved.rawValue || entity.kind == TripActivityEventKind.discoveryRejected.rawValue {
                if let data = entity.payloadData,
                   let payload = try? JSONDecoder().decode([String: String].self, from: data),
                   payload[TripActivityEventPayloadKey.gameInstanceId] == gidStr {
                    ctx.delete(entity)
                }
            }
        } else {
            var descriptor = FetchDescriptor<TripActivityEventEntity>(
                predicate: #Predicate<TripActivityEventEntity> { $0.sessionId == sid }
            )
            let entities = try ctx.fetch(descriptor)
            for entity in entities {
                ctx.delete(entity)
            }
        }
        try ctx.save()
    }

    func deleteAllEventsForGame(sessionId: UUID, gameInstanceId: UUID) throws {
        guard let ctx = modelContext else { throw TripActivityEventRepositoryError.noModelContext }
        let sid = sessionId.uuidString
        let gidStr = gameInstanceId.uuidString
        var descriptor = FetchDescriptor<TripActivityEventEntity>(
            predicate: #Predicate<TripActivityEventEntity> { $0.sessionId == sid }
        )
        let entities = try ctx.fetch(descriptor)
        for entity in entities {
            guard let data = entity.payloadData,
                  let payload = try? JSONDecoder().decode([String: String].self, from: data),
                  payload[TripActivityEventPayloadKey.gameInstanceId] == gidStr else { continue }
            ctx.delete(entity)
        }
        try ctx.save()
    }

    func deleteEvent(id: String) throws {
        guard let ctx = modelContext else { throw TripActivityEventRepositoryError.noModelContext }
        guard let entity = try Self.fetchEntity(id: id, context: ctx) else { return }
        ctx.delete(entity)
        try ctx.save()
    }

    private static func fetchEntity(id: String, context: ModelContext) throws -> TripActivityEventEntity? {
        let searchId = id
        let descriptor = FetchDescriptor<TripActivityEventEntity>(
            predicate: #Predicate<TripActivityEventEntity> { $0.id == searchId }
        )
        return try context.fetch(descriptor).first
    }

    private static func payloadsEqual(_ a: [String: String]?, _ b: [String: String]?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case (let x?, nil), (nil, let x?): return x.isEmpty
        case (let x?, let y?): return x == y
        }
    }

    /// Firestore round-trip vs local `Date` can differ by a fraction of a second.
    private static func timestampsEffectivelyEqual(_ a: Date, _ b: Date) -> Bool {
        abs(a.timeIntervalSince1970 - b.timeIntervalSince1970) < 0.002
    }

    private func entityToEvent(_ entity: TripActivityEventEntity) -> TripActivityEvent {
        let payload: [String: String]? = entity.payloadData.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }
        let kind = TripActivityEventKind(rawValue: entity.kind) ?? .regionFound
        return TripActivityEvent(
            id: entity.id,
            sessionId: UUID(uuidString: entity.sessionId) ?? UUID(),
            kind: kind,
            timestamp: entity.timestamp,
            actorId: entity.actorId,
            payload: payload
        )
    }

}

enum TripActivityEventRepositoryError: Error, LocalizedError {
    case noModelContext
    case idCollision(id: String)

    var errorDescription: String? {
        switch self {
        case .noModelContext: return "Model context not set"
        case .idCollision(let id): return "Trip activity event id collision: \(id)"
        }
    }
}
