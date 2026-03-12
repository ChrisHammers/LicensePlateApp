//
//  MockTripSessionRepository.swift
//  LicensePlateAppTests
//
//  Step 13 — Test double for TripSessionRepositoryProtocol. In-memory store; configurable errors.
//

import Foundation
import SwiftData
@testable import LicensePlateApp

@MainActor
final class MockTripSessionRepository: TripSessionRepositoryProtocol {
    private var sessions: [UUID: TripSession] = [:]
    private var context: ModelContext?
    var shouldThrow = false
    var lastSyncedAtToReturn: Date?

    func setModelContext(_ context: ModelContext) {
        self.context = context
    }

    func create(session: TripSession) throws {
        if shouldThrow { throw NSError(domain: "MockTripSessionRepository", code: -1, userInfo: nil) }
        sessions[session.id] = session
    }

    func loadActiveSessions(userId: String?) throws -> [TripSession] {
        if shouldThrow { throw NSError(domain: "MockTripSessionRepository", code: -1, userInfo: nil) }
        return sessions.values.filter { $0.status == .active }
    }

    func loadPendingSessions(userId: String?) throws -> [TripSession] {
        if shouldThrow { throw NSError(domain: "MockTripSessionRepository", code: -1, userInfo: nil) }
        return []
    }

    func loadArchivedSessions(userId: String?, limit: Int) throws -> [TripSession] {
        if shouldThrow { throw NSError(domain: "MockTripSessionRepository", code: -1, userInfo: nil) }
        return Array(sessions.values.filter { $0.status == .ended }.sorted { ($0.endedAt ?? .distantPast) > ($1.endedAt ?? .distantPast) }.prefix(limit))
    }

    func addParticipant(sessionId: UUID, participant: TripParticipant) throws {
        if shouldThrow { throw NSError(domain: "MockTripSessionRepository", code: -1, userInfo: nil) }
        if var session = sessions[sessionId] {
            var participants = session.participants
            participants.append(participant)
            session.participants = participants
            sessions[sessionId] = session
        }
    }

    func removeParticipant(sessionId: UUID, userId: String) throws {
        if shouldThrow { throw NSError(domain: "MockTripSessionRepository", code: -1, userInfo: nil) }
        if var session = sessions[sessionId] {
            session.participants.removeAll { $0.userId == userId }
            sessions[sessionId] = session
        }
    }

    func updateStatus(sessionId: UUID, status: TripStatus) throws {
        if shouldThrow { throw NSError(domain: "MockTripSessionRepository", code: -1, userInfo: nil) }
        if var session = sessions[sessionId] {
            session.status = status
            if status == .active { session.startedAt = session.startedAt ?? Date() }
            if status == .ended { session.endedAt = Date() }
            sessions[sessionId] = session
        }
    }

    func save(session: TripSession) throws {
        if shouldThrow { throw NSError(domain: "MockTripSessionRepository", code: -1, userInfo: nil) }
        sessions[session.id] = session
    }

    func session(byId id: UUID) throws -> TripSession? {
        if shouldThrow { throw NSError(domain: "MockTripSessionRepository", code: -1, userInfo: nil) }
        return sessions[id]
    }

    func lastSyncedAt(sessionId: UUID) -> Date? {
        lastSyncedAtToReturn
    }

    /// Test helper: seed sessions
    func seed(_ session: TripSession) {
        sessions[session.id] = session
    }

    /// Test helper: clear all
    func clear() {
        sessions.removeAll()
    }
}
