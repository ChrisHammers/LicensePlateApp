//
//  PendingTripLeaveRepository.swift
//  LicensePlateApp
//
//  Step 14 — SwiftData persistence for offline leave pending reconciliation.
//

import Foundation
import SwiftData
import Combine

@MainActor
final class PendingTripLeaveRepository: ObservableObject, PendingTripLeaveRepositoryProtocol {

    static let shared = PendingTripLeaveRepository()

    private var modelContext: ModelContext?

    private init() {}

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func insertPending(sessionId: UUID, userId: String) throws {
        guard let ctx = modelContext else { throw PendingTripLeaveRepositoryError.noModelContext }
        let sid = sessionId.uuidString
        if try hasPending(sessionId: sessionId, userId: userId) {
            return
        }
        ctx.insert(PendingTripLeaveEntity(sessionId: sid, userId: userId))
        try ctx.save()
    }

    func deletePending(sessionId: UUID, userId: String) throws {
        guard let ctx = modelContext else { throw PendingTripLeaveRepositoryError.noModelContext }
        let sid = sessionId.uuidString
        var descriptor = FetchDescriptor<PendingTripLeaveEntity>(
            predicate: #Predicate<PendingTripLeaveEntity> { $0.sessionId == sid && $0.userId == userId }
        )
        descriptor.fetchLimit = 1
        if let row = try ctx.fetch(descriptor).first {
            ctx.delete(row)
            try ctx.save()
        }
    }

    func hasPending(sessionId: UUID, userId: String) throws -> Bool {
        guard let ctx = modelContext else { throw PendingTripLeaveRepositoryError.noModelContext }
        let sid = sessionId.uuidString
        var descriptor = FetchDescriptor<PendingTripLeaveEntity>(
            predicate: #Predicate<PendingTripLeaveEntity> { $0.sessionId == sid && $0.userId == userId }
        )
        descriptor.fetchLimit = 1
        return try ctx.fetch(descriptor).first != nil
    }

    func sessionIdsPendingLeave(userId: String) throws -> Set<UUID> {
        guard let ctx = modelContext else { throw PendingTripLeaveRepositoryError.noModelContext }
        let descriptor = FetchDescriptor<PendingTripLeaveEntity>(
            predicate: #Predicate<PendingTripLeaveEntity> { $0.userId == userId }
        )
        let rows = try ctx.fetch(descriptor)
        var out = Set<UUID>()
        for row in rows {
            if let u = UUID(uuidString: row.sessionId) {
                out.insert(u)
            }
        }
        return out
    }

    /// Hard sign-out: drop all pending leave rows locally (do not send leave callables).
    func deleteAllLocal() throws {
        guard let ctx = modelContext else { throw PendingTripLeaveRepositoryError.noModelContext }
        try ctx.delete(model: PendingTripLeaveEntity.self)
        try ctx.save()
    }
}

enum PendingTripLeaveRepositoryError: Error, LocalizedError {
    case noModelContext

    var errorDescription: String? {
        switch self {
        case .noModelContext: return "Model context not set"
        }
    }
}
