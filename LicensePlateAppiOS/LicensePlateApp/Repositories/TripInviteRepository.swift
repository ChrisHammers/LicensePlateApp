//
//  TripInviteRepository.swift
//  LicensePlateApp
//
//  Step 04 — Local-first persistence for TripInvite. SwiftData only for MVP.
//

import Foundation
import SwiftData
import Combine

@MainActor
final class TripInviteRepository: ObservableObject, TripInviteRepositoryProtocol {

    static let shared = TripInviteRepository()

    private var modelContext: ModelContext?

    @Published private(set) var tripInvites: [TripInvite] = []

    private init() {}

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    // MARK: - Queries

    func getIncomingInvites(userId: String) throws -> [TripInvite] {
        guard let ctx = modelContext else { throw TripInviteRepositoryError.noModelContext }
        let searchUserId = userId
        let pending = TripInvite.TripInviteStatus.pending.rawValue
        var descriptor = FetchDescriptor<TripInvite>(
            predicate: #Predicate<TripInvite> { invite in
                invite.toUserId == searchUserId && invite.status == pending
            }
        )
        descriptor.sortBy = [SortDescriptor(\.createdAt, order: .reverse)]
        return try ctx.fetch(descriptor)
    }

    func getOutgoingInvites(userId: String) throws -> [TripInvite] {
        guard let ctx = modelContext else { throw TripInviteRepositoryError.noModelContext }
        let searchUserId = userId
        let sent = TripInvite.TripInviteStatus.sent.rawValue
        let pending = TripInvite.TripInviteStatus.pending.rawValue
        var descriptor = FetchDescriptor<TripInvite>(
            predicate: #Predicate<TripInvite> { invite in
                invite.fromUserId == searchUserId && (invite.status == sent || invite.status == pending)
            }
        )
        descriptor.sortBy = [SortDescriptor(\.createdAt, order: .reverse)]
        return try ctx.fetch(descriptor)
    }

    // MARK: - Mutations

    func acceptInvite(inviteId: String, userId: String) throws {
        guard let ctx = modelContext else { throw TripInviteRepositoryError.noModelContext }
        guard let invite = try fetchInvite(byId: inviteId, context: ctx) else {
            throw TripInviteRepositoryError.inviteNotFound(inviteId)
        }
        guard invite.toUserId == userId else {
            throw TripInviteRepositoryError.notRecipient
        }
        invite.statusEnum = .accepted
        invite.respondedAt = Date()
        try ctx.save()
        refreshPublishedInvites(userId: userId)
    }

    func declineInvite(inviteId: String, userId: String) throws {
        guard let ctx = modelContext else { throw TripInviteRepositoryError.noModelContext }
        guard let invite = try fetchInvite(byId: inviteId, context: ctx) else {
            throw TripInviteRepositoryError.inviteNotFound(inviteId)
        }
        guard invite.toUserId == userId else {
            throw TripInviteRepositoryError.notRecipient
        }
        invite.statusEnum = .declined
        invite.respondedAt = Date()
        try ctx.save()
        refreshPublishedInvites(userId: userId)
    }

    func cancelInvite(inviteId: String, userId: String) throws {
        guard let ctx = modelContext else { throw TripInviteRepositoryError.noModelContext }
        guard let invite = try fetchInvite(byId: inviteId, context: ctx) else {
            throw TripInviteRepositoryError.inviteNotFound(inviteId)
        }
        guard invite.fromUserId == userId else {
            throw TripInviteRepositoryError.notSender
        }
        invite.statusEnum = .canceled
        invite.respondedAt = Date()
        try ctx.save()
        refreshPublishedInvites(userId: userId)
    }

    func createInvite(
        tripSessionId: String,
        tripName: String,
        fromUserId: String,
        toUserId: String,
        expiresAt: Date
    ) throws -> TripInvite {
        guard let ctx = modelContext else { throw TripInviteRepositoryError.noModelContext }
        let inviteId = UUID().uuidString
        let invite = TripInvite(
            inviteId: inviteId,
            tripSessionId: tripSessionId,
            tripName: tripName,
            fromUserId: fromUserId,
            toUserId: toUserId,
            status: .sent,
            createdAt: Date(),
            expiresAt: expiresAt
        )
        ctx.insert(invite)
        try ctx.save()
        refreshPublishedInvites(userId: fromUserId)
        return invite
    }

    /// Refresh the published list for a user (incoming + outgoing).
    /// NotificationRoutingService subscribes to `tripInvites` and shows a local notification only when new incoming invites are detected.
    func refreshPublishedInvites(userId: String) {
        guard let ctx = modelContext else { return }
        let searchUserId = userId
        var descriptor = FetchDescriptor<TripInvite>(
            predicate: #Predicate<TripInvite> { invite in
                invite.fromUserId == searchUserId || invite.toUserId == searchUserId
            }
        )
        descriptor.sortBy = [SortDescriptor(\.createdAt, order: .reverse)]
        tripInvites = (try? ctx.fetch(descriptor)) ?? []
    }

    // MARK: - Helpers

    private func fetchInvite(byId id: String, context: ModelContext) throws -> TripInvite? {
        let descriptor = FetchDescriptor<TripInvite>(
            predicate: #Predicate<TripInvite> { $0.inviteId == id }
        )
        return try context.fetch(descriptor).first
    }
}

enum TripInviteRepositoryError: Error, LocalizedError {
    case noModelContext
    case inviteNotFound(String)
    case notRecipient
    case notSender

    var errorDescription: String? {
        switch self {
        case .noModelContext: return "Model context not set"
        case .inviteNotFound(let id): return "Trip invite not found: \(id)"
        case .notRecipient: return "User is not the recipient of this invite"
        case .notSender: return "User is not the sender of this invite"
        }
    }
}

// MARK: - Notification (minimal hook for future push/local notification)
extension Notification.Name {
    /// Post when trip invites are refreshed (e.g. after sync). Use for local/push notification flow.
    static let tripInviteReceived = Notification.Name("tripInviteReceived")
}
