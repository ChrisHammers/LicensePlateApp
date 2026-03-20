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
    func events(sessionId: UUID, limit: Int?) throws -> [TripActivityEvent]
    func discoveries(sessionId: UUID, gameInstanceId: UUID?) throws -> [GameDiscovery]
    func foundRegions(sessionId: UUID, gameInstanceId: UUID?) throws -> [FoundRegion]
    /// Remove all events for a session (or for a specific game when gameInstanceId is provided). Used for "Reset Trip".
    func deleteEvents(sessionId: UUID, gameInstanceId: UUID?) throws
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
        let discoveryEvents = allEvents.filter { $0.kind == .regionFound || $0.kind == .regionRemoved }
        var byRegion: [String: (TripActivityEvent, [String: String])] = [:]
        for event in discoveryEvents {
            let payload = event.payload ?? [:]
            guard let regionId = payload[TripActivityEventPayloadKey.regionId] else { continue }
            if let filterGid = gameInstanceId,
               let payloadGid = payload[TripActivityEventPayloadKey.gameInstanceId],
               UUID(uuidString: payloadGid) != filterGid {
                continue
            }
            if event.kind == .regionRemoved {
                byRegion.removeValue(forKey: regionId)
            } else {
                byRegion[regionId] = (event, payload)
            }
        }
        return byRegion.values.sorted { ($0.0.timestamp) < ($1.0.timestamp) }.compactMap { event, payload in
            let targetId = payload[TripActivityEventPayloadKey.regionId] ?? ""
            guard !targetId.isEmpty else { return nil }
            let gid = (payload[TripActivityEventPayloadKey.gameInstanceId].flatMap { UUID(uuidString: $0) }) ?? gameInstanceId ?? sessionId
            let participantId = payload[TripActivityEventPayloadKey.participantId] ?? event.actorId ?? ""
            let inputMethod = FoundRegion.InputMethod(rawValue: payload[TripActivityEventPayloadKey.inputMethod] ?? FoundRegion.InputMethod.list.rawValue) ?? .list
            return GameDiscovery(
                gameInstanceId: gid,
                participantId: participantId,
                targetId: targetId,
                discoveredAt: event.timestamp,
                inputMethod: inputMethod,
                location: nil
            )
        }
    }

    func foundRegions(sessionId: UUID, gameInstanceId: UUID?) throws -> [FoundRegion] {
        let allEvents = try events(sessionId: sessionId, limit: nil)
        let discoveryEvents = allEvents.filter { $0.kind == .regionFound || $0.kind == .regionRemoved }
        var byRegion: [String: (TripActivityEvent, [String: String])] = [:]
        for event in discoveryEvents {
            let payload = event.payload ?? [:]
            guard let regionId = payload[TripActivityEventPayloadKey.regionId] else { continue }
            if let filterGid = gameInstanceId,
               let payloadGid = payload[TripActivityEventPayloadKey.gameInstanceId],
               UUID(uuidString: payloadGid) != filterGid {
                continue
            }
            if event.kind == .regionRemoved {
                byRegion.removeValue(forKey: regionId)
            } else {
                byRegion[regionId] = (event, payload)
            }
        }
        return byRegion.values.sorted { ($0.0.timestamp) < ($1.0.timestamp) }.map { event, payload in
            let inputMethod = FoundRegion.InputMethod(rawValue: payload[TripActivityEventPayloadKey.inputMethod] ?? FoundRegion.InputMethod.list.rawValue) ?? .list
            return FoundRegion(
                regionID: payload[TripActivityEventPayloadKey.regionId] ?? "",
                foundAt: event.timestamp,
                inputMethod: inputMethod,
                foundBy: payload[TripActivityEventPayloadKey.participantId] ?? event.actorId,
                foundAtLocation: nil
            )
        }
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

    var errorDescription: String? {
        switch self {
        case .noModelContext: return "Model context not set"
        }
    }
}
