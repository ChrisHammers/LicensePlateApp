//
//  MockTripInviteRepository.swift
//  LicensePlateAppTests
//
//  Step 13 — Test double for TripInviteRepositoryProtocol. In-memory invite list; configurable errors.
//

import Foundation
import SwiftData
@testable import LicensePlateApp

@MainActor
final class MockTripInviteRepository: TripInviteRepositoryProtocol {
    private var incoming: [TripInvite] = []
    private var outgoing: [TripInvite] = []
    private var context: ModelContext?
    var shouldThrow = false

    func setModelContext(_ context: ModelContext) {
        self.context = context
    }

    func getIncomingInvites(userId: String) throws -> [TripInvite] {
        if shouldThrow { throw NSError(domain: "MockTripInviteRepository", code: -1, userInfo: nil) }
        return incoming.filter { $0.toUserId == userId }
    }

    func getOutgoingInvites(userId: String) throws -> [TripInvite] {
        if shouldThrow { throw NSError(domain: "MockTripInviteRepository", code: -1, userInfo: nil) }
        return outgoing.filter { $0.fromUserId == userId }
    }

    func acceptInvite(inviteId: String, userId: String) throws {
        if shouldThrow { throw NSError(domain: "MockTripInviteRepository", code: -1, userInfo: nil) }
        if let idx = incoming.firstIndex(where: { $0.inviteId == inviteId }) {
            incoming[idx].status = TripInvite.TripInviteStatus.accepted.rawValue
            incoming[idx].respondedAt = Date()
        }
    }

    func declineInvite(inviteId: String, userId: String) throws {
        if shouldThrow { throw NSError(domain: "MockTripInviteRepository", code: -1, userInfo: nil) }
        if let idx = incoming.firstIndex(where: { $0.inviteId == inviteId }) {
            incoming[idx].status = TripInvite.TripInviteStatus.declined.rawValue
            incoming[idx].respondedAt = Date()
        }
    }

    func cancelInvite(inviteId: String, userId: String) throws {
        if shouldThrow { throw NSError(domain: "MockTripInviteRepository", code: -1, userInfo: nil) }
        outgoing.removeAll { $0.inviteId == inviteId }
        incoming.removeAll { $0.inviteId == inviteId }
    }

    func createInvite(
        tripSessionId: String,
        tripName: String,
        fromUserId: String,
        toUserId: String,
        expiresAt: Date
    ) throws -> TripInvite {
        if shouldThrow { throw NSError(domain: "MockTripInviteRepository", code: -1, userInfo: nil) }
        let invite = TripInvite(
            inviteId: UUID().uuidString,
            tripSessionId: tripSessionId,
            tripName: tripName,
            fromUserId: fromUserId,
            toUserId: toUserId,
            status: .sent,
            createdAt: Date(),
            expiresAt: expiresAt
        )
        outgoing.append(invite)
        incoming.append(invite)
        return invite
    }

    /// Test helper: seed incoming invites (e.g. from fixture params; caller creates TripInvite in context and passes)
    func seedIncoming(_ invite: TripInvite) {
        incoming.append(invite)
    }

    /// Test helper: clear
    func clear() {
        incoming.removeAll()
        outgoing.removeAll()
    }
}
