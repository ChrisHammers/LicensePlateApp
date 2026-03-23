//
//  TripInviteRepositoryProtocol.swift
//  LicensePlateApp
//
//  Step 04 — Protocol for trip invite persistence. Step 08 — backend mirror + async callables.
//

import Combine
import Foundation
import SwiftData

@MainActor
protocol TripInviteRepositoryProtocol: AnyObject {
    /// Fires after Firestore mirror updates (or mock mutations) so ViewModels can reload without casting to concrete type.
    var inviteSnapshotSignal: AnyPublisher<Void, Never> { get }

    func setModelContext(_ context: ModelContext)

    func startListening(userId: String)
    func stopListening()

    func getIncomingInvites(userId: String) throws -> [TripInvite]
    func getOutgoingInvites(userId: String) throws -> [TripInvite]

    func acceptInvite(inviteId: String, userId: String) async throws
    func declineInvite(inviteId: String, userId: String) async throws
    func cancelInvite(inviteId: String, userId: String) async throws

    /// Creates invite on server; returns Firestore document id.
    func sendTripInvite(
        tripSessionId: String,
        tripName: String,
        fromUserId: String,
        toUserId: String,
        expiresAt: Date?
    ) async throws -> String
}
