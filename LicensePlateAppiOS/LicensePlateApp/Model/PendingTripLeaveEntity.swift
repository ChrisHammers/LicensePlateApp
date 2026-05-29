//
//  PendingTripLeaveEntity.swift
//  LicensePlateApp
//
//  Step 14 — Durable local row: user initiated leave; server confirmation pending.
//

import Foundation
import SwiftData

@Model
final class PendingTripLeaveEntity {
    var sessionId: String
    var userId: String
    var createdAt: Date

    init(sessionId: String, userId: String, createdAt: Date = .now) {
        self.sessionId = sessionId
        self.userId = userId
        self.createdAt = createdAt
    }
}
