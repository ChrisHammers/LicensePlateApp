//
//  MockTripInviteRepository.swift
//  LicensePlateAppTests
//
//  Test double for TripInviteRepositoryProtocol. In-memory invites; configurable errors.
//

import Combine
import Foundation
import SwiftData
@testable import LicensePlateApp

@MainActor
final class MockTripInviteRepository: TripInviteRepositoryProtocol {
    private let inviteSnapshotSubject = PassthroughSubject<Void, Never>()
    var inviteSnapshotSignal: AnyPublisher<Void, Never> {
        inviteSnapshotSubject.eraseToAnyPublisher()
    }

    private var invites: [TripInvite] = []

    var shouldThrow = false

    func setModelContext(_ context: ModelContext) {
        _ = context
    }

    func startListening(userId: String) {
        _ = userId
    }

    func stopListening() {}

    func getIncomingInvites(userId: String) throws -> [TripInvite] {
        if shouldThrow { throw NSError(domain: "MockTripInviteRepository", code: -1, userInfo: nil) }
        let pending = TripInvite.TripInviteStatus.pending.rawValue
        return invites
            .filter { $0.toUserId == userId && $0.status == pending }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func getOutgoingInvites(userId: String) throws -> [TripInvite] {
        if shouldThrow { throw NSError(domain: "MockTripInviteRepository", code: -1, userInfo: nil) }
        let pending = TripInvite.TripInviteStatus.pending.rawValue
        let sent = TripInvite.TripInviteStatus.sent.rawValue
        return invites
            .filter { $0.fromUserId == userId && ($0.status == pending || $0.status == sent) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func getInvites(forTripSessionId tripSessionId: String) throws -> [TripInvite] {
        if shouldThrow { throw NSError(domain: "MockTripInviteRepository", code: -1, userInfo: nil) }
        return invites
            .filter { $0.tripSessionId == tripSessionId }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func hasPendingInvite(tripSessionId: String, toUserId: String) throws -> Bool {
        if shouldThrow { throw NSError(domain: "MockTripInviteRepository", code: -1, userInfo: nil) }
        return invites.contains {
            $0.tripSessionId == tripSessionId
                && $0.toUserId == toUserId
                && $0.statusEnum == .pending
        }
    }

    func acceptInvite(inviteId: String, userId: String) async throws {
        if shouldThrow { throw NSError(domain: "MockTripInviteRepository", code: -1, userInfo: nil) }
        guard let idx = invites.firstIndex(where: { $0.inviteId == inviteId && $0.toUserId == userId }) else {
            return
        }
        invites[idx].statusEnum = .accepted
        invites[idx].respondedAt = Date()
        inviteSnapshotSubject.send()
    }

    func declineInvite(inviteId: String, userId: String) async throws {
        if shouldThrow { throw NSError(domain: "MockTripInviteRepository", code: -1, userInfo: nil) }
        guard let idx = invites.firstIndex(where: { $0.inviteId == inviteId && $0.toUserId == userId }) else {
            return
        }
        invites[idx].statusEnum = .declined
        invites[idx].respondedAt = Date()
        inviteSnapshotSubject.send()
    }

    func cancelInvite(inviteId: String, userId: String) async throws {
        if shouldThrow { throw NSError(domain: "MockTripInviteRepository", code: -1, userInfo: nil) }
        guard let idx = invites.firstIndex(where: { $0.inviteId == inviteId && $0.fromUserId == userId }) else {
            return
        }
        invites[idx].statusEnum = .canceled
        invites[idx].respondedAt = Date()
        inviteSnapshotSubject.send()
    }

    func sendTripInvite(
        tripSessionId: String,
        tripName: String,
        fromUserId: String,
        toUserId: String,
        expiresAt: Date?
    ) async throws -> String {
        if shouldThrow { throw NSError(domain: "MockTripInviteRepository", code: -1, userInfo: nil) }
        let id = UUID().uuidString
        let exp = expiresAt ?? Date().addingTimeInterval(86400 * 7)
        let invite = TripInvite(
            inviteId: id,
            tripSessionId: tripSessionId,
            tripName: tripName,
            fromUserId: fromUserId,
            toUserId: toUserId,
            status: .pending,
            createdAt: Date(),
            expiresAt: exp
        )
        invites.append(invite)
        inviteSnapshotSubject.send()
        return id
    }

    /// Seed an invite for tests (caller-owned instance).
    func seed(_ invite: TripInvite) {
        invites.append(invite)
    }

    func clear() {
        invites.removeAll()
    }
}
