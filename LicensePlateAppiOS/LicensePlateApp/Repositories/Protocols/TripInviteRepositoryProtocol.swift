//
//  TripInviteRepositoryProtocol.swift
//  LicensePlateApp
//
//  Step 04 — Protocol for trip invite persistence. Enables test doubles.
//

import Foundation
import SwiftData

@MainActor
protocol TripInviteRepositoryProtocol: AnyObject {
    func setModelContext(_ context: ModelContext)

    func getIncomingInvites(userId: String) throws -> [TripInvite]
    func getOutgoingInvites(userId: String) throws -> [TripInvite]
    func acceptInvite(inviteId: String, userId: String) throws
    func declineInvite(inviteId: String, userId: String) throws
    func cancelInvite(inviteId: String, userId: String) throws
    func createInvite(
        tripSessionId: String,
        tripName: String,
        fromUserId: String,
        toUserId: String,
        expiresAt: Date
    ) throws -> TripInvite
}
