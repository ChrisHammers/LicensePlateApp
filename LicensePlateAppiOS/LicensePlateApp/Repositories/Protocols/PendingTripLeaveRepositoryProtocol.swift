//
//  PendingTripLeaveRepositoryProtocol.swift
//  LicensePlateApp
//
//  Step 14 — Pending voluntary leave before server reconciles membership.
//

import Foundation
import SwiftData

@MainActor
protocol PendingTripLeaveRepositoryProtocol: AnyObject {
    func setModelContext(_ context: ModelContext)
    func insertPending(sessionId: UUID, userId: String) throws
    func deletePending(sessionId: UUID, userId: String) throws
    func hasPending(sessionId: UUID, userId: String) throws -> Bool
    /// Session ids with a pending leave row for this user.
    func sessionIdsPendingLeave(userId: String) throws -> Set<UUID>
}
