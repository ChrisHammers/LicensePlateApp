//
//  XpLedgerEvent.swift
//  LicensePlateApp
//
//  Append-only XP ledger row (domain value). Totals are derived from these events.
//

import Foundation

struct XpLedgerEvent: Identifiable, Codable, Sendable, Equatable {
    var id: String
    var userId: String
    var sessionId: UUID
    var gameInstanceId: UUID
    /// Source gameplay event (e.g. `TripActivityEvent.id`).
    var sourceEventId: String
    var sourceEventType: String
    /// Target identifier (e.g. region id).
    var itemId: String
    var grantKind: XpGrantKind
    var status: XpLedgerStatus
    var xpDelta: Int
    var reasonCode: XpReasonCode
    /// Canonical idempotency key string (from `XpUniquenessKey.storageString` or builder).
    var xpUniquenessKey: String
    var createdAt: Date
    var resolvedAt: Date?
    /// Optional metadata: game mode, input method, outcome labels, etc.
    var metadata: [String: String]?

    init(
        id: String = UUID().uuidString,
        userId: String,
        sessionId: UUID,
        gameInstanceId: UUID,
        sourceEventId: String,
        sourceEventType: String,
        itemId: String,
        grantKind: XpGrantKind,
        status: XpLedgerStatus,
        xpDelta: Int,
        reasonCode: XpReasonCode,
        xpUniquenessKey: String,
        createdAt: Date = .now,
        resolvedAt: Date? = nil,
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.userId = userId
        self.sessionId = sessionId
        self.gameInstanceId = gameInstanceId
        self.sourceEventId = sourceEventId
        self.sourceEventType = sourceEventType
        self.itemId = itemId
        self.grantKind = grantKind
        self.status = status
        self.xpDelta = xpDelta
        self.reasonCode = reasonCode
        self.xpUniquenessKey = xpUniquenessKey
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
        self.metadata = metadata
    }
}
