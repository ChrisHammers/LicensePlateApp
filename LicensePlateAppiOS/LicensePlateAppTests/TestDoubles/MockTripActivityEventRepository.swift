//
//  MockTripActivityEventRepository.swift
//  LicensePlateAppTests
//
//  Step 04 — Test double for TripActivityEventRepositoryProtocol. In-memory event store; records appends for verification.
//

import Foundation
import SwiftData
@testable import LicensePlateApp

@MainActor
final class MockTripActivityEventRepository: TripActivityEventRepositoryProtocol {
    private var events: [TripActivityEvent] = []
    var shouldThrow = false

    func setModelContext(_ context: ModelContext) {}

    func append(_ event: TripActivityEvent) throws {
        if shouldThrow { throw NSError(domain: "MockTripActivityEventRepository", code: -1, userInfo: nil) }
        events.append(event)
    }

    func events(sessionId: UUID, limit: Int?) throws -> [TripActivityEvent] {
        if shouldThrow { throw NSError(domain: "MockTripActivityEventRepository", code: -1, userInfo: nil) }
        var list = events.filter { $0.sessionId == sessionId }.sorted { $0.timestamp < $1.timestamp }
        if let limit = limit {
            list = Array(list.prefix(limit))
        }
        return list
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
        if shouldThrow { throw NSError(domain: "MockTripActivityEventRepository", code: -1, userInfo: nil) }
        if let gid = gameInstanceId {
            let gidStr = gid.uuidString
            events.removeAll { event in
                guard event.sessionId == sessionId else { return false }
                guard event.kind == .regionFound || event.kind == .regionRemoved else { return false }
                return event.payload?[TripActivityEventPayloadKey.gameInstanceId] == gidStr
            }
        } else {
            events.removeAll { $0.sessionId == sessionId }
        }
    }

    /// Test helper: appended events (e.g. to assert trip_started, game_started)
    func appendedEvents() -> [TripActivityEvent] {
        events
    }

    func clear() {
        events.removeAll()
    }
}
