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

    @discardableResult
    func appendIfAbsent(_ event: TripActivityEvent) throws -> Bool {
        if shouldThrow { throw NSError(domain: "MockTripActivityEventRepository", code: -1, userInfo: nil) }
        if let idx = events.firstIndex(where: { $0.id == event.id }) {
            let existing = events[idx]
            guard existing.sessionId == event.sessionId,
                  existing.kind == event.kind,
                  existing.actorId == event.actorId,
                  existing.payload == event.payload else {
                throw TripActivityEventRepositoryError.idCollision(id: event.id)
            }
            return false
        }
        events.append(event)
        return true
    }

    func importEventsIfAbsent(_ events: [TripActivityEvent]) throws {
        for event in events {
            _ = try appendIfAbsent(event)
        }
    }

    func event(byId id: String) throws -> TripActivityEvent? {
        if shouldThrow { throw NSError(domain: "MockTripActivityEventRepository", code: -1, userInfo: nil) }
        return events.first { $0.id == id }
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
        return TripActivityEventDiscoveryReplay.replay(events: allEvents, gameInstanceFilter: gameInstanceId).discoveries
    }

    func foundRegions(sessionId: UUID, gameInstanceId: UUID?) throws -> [FoundRegion] {
        let allEvents = try events(sessionId: sessionId, limit: nil)
        return TripActivityEventDiscoveryReplay.replay(events: allEvents, gameInstanceFilter: gameInstanceId).foundRegions
    }

    func deleteEvents(sessionId: UUID, gameInstanceId: UUID?) throws {
        if shouldThrow { throw NSError(domain: "MockTripActivityEventRepository", code: -1, userInfo: nil) }
        if let gid = gameInstanceId {
            let gidStr = gid.uuidString
            events.removeAll { event in
                guard event.sessionId == sessionId else { return false }
                guard event.kind == .regionFound || event.kind == .regionRemoved || event.kind == .discoveryRejected else { return false }
                return event.payload?[TripActivityEventPayloadKey.gameInstanceId] == gidStr
            }
        } else {
            events.removeAll { $0.sessionId == sessionId }
        }
    }

    func deleteAllEventsForGame(sessionId: UUID, gameInstanceId: UUID) throws {
        if shouldThrow { throw NSError(domain: "MockTripActivityEventRepository", code: -1, userInfo: nil) }
        let gidStr = gameInstanceId.uuidString
        events.removeAll { event in
            guard event.sessionId == sessionId else { return false }
            return event.payload?[TripActivityEventPayloadKey.gameInstanceId] == gidStr
        }
    }

    func deleteEvent(id: String) throws {
        if shouldThrow { throw NSError(domain: "MockTripActivityEventRepository", code: -1, userInfo: nil) }
        events.removeAll { $0.id == id }
    }

    /// Test helper: appended events (e.g. to assert trip_started, game_started)
    func appendedEvents() -> [TripActivityEvent] {
        events
    }

    func clear() {
        events.removeAll()
    }
}
