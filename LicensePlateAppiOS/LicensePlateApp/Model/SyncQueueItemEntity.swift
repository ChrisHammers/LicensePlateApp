//
//  SyncQueueItemEntity.swift
//  LicensePlateApp
//
//  Step 06 — SwiftData persistence for sync queue items (durable, survives restarts).
//

import Foundation
import SwiftData

@Model
final class SyncQueueItemEntity {
    var id: String
    var kind: String
    var state: String
    var attemptCount: Int
    var createdAt: Date
    var updatedAt: Date
    var nextRetryAt: Date?
    var payloadSessionId: String?
    var payloadEventId: String?
    var payloadData: Data?

    init(
        id: String,
        kind: String,
        state: String,
        attemptCount: Int,
        createdAt: Date,
        updatedAt: Date,
        nextRetryAt: Date? = nil,
        payloadSessionId: String? = nil,
        payloadEventId: String? = nil,
        payloadData: Data? = nil
    ) {
        self.id = id
        self.kind = kind
        self.state = state
        self.attemptCount = attemptCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.nextRetryAt = nextRetryAt
        self.payloadSessionId = payloadSessionId
        self.payloadEventId = payloadEventId
        self.payloadData = payloadData
    }
}
