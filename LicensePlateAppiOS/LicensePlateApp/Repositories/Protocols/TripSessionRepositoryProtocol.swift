//
//  TripSessionRepositoryProtocol.swift
//  LicensePlateApp
//
//  Protocol for trip session persistence. Enables test doubles. Step 03 — repository layer.
//

import Foundation
import SwiftData

@MainActor
protocol TripSessionRepositoryProtocol: AnyObject {
    func setModelContext(_ context: ModelContext)

    func create(session: TripSession) throws
    func loadActiveSessions(userId: String?) throws -> [TripSession]
    func loadPendingSessions(userId: String?) throws -> [TripSession]
    func loadArchivedSessions(userId: String?, limit: Int) throws -> [TripSession]
    func addParticipant(sessionId: UUID, participant: TripParticipant) throws
    func removeParticipant(sessionId: UUID, userId: String) throws
    func updateStatus(sessionId: UUID, status: TripStatus) throws
    func save(session: TripSession) throws
    func session(byId id: UUID) throws -> TripSession?

    /// Placeholder for future sync; returns nil until lastSyncedAt is stored on entity.
    func lastSyncedAt(sessionId: UUID) -> Date?
}
