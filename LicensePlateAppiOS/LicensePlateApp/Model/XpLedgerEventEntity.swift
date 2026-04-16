//
//  XpLedgerEventEntity.swift
//  LicensePlateApp
//
//  SwiftData persistence for append-only XP ledger rows.
//

import Foundation
import SwiftData

@Model
final class XpLedgerEventEntity {
    var id: String
    var userId: String
    var sessionId: String
    var gameInstanceId: String
    var sourceEventId: String
    var sourceEventType: String
    var itemId: String
    var grantKind: String
    var status: String
    var xpDelta: Int
    var reasonCode: String
    var xpUniquenessKey: String
    var createdAt: Date
    var resolvedAt: Date?
    /// JSON-encoded `[String: String]` metadata.
    var metadataData: Data?

    init(
        id: String,
        userId: String,
        sessionId: String,
        gameInstanceId: String,
        sourceEventId: String,
        sourceEventType: String,
        itemId: String,
        grantKind: String,
        status: String,
        xpDelta: Int,
        reasonCode: String,
        xpUniquenessKey: String,
        createdAt: Date,
        resolvedAt: Date? = nil,
        metadataData: Data? = nil
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
        self.metadataData = metadataData
    }
}
