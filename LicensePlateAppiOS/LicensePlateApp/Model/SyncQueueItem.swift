//
//  SyncQueueItem.swift
//  LicensePlateApp
//
//  Step 06 — Domain model for durable sync queue item (state, retry, payload refs).
//

import Foundation

/// State of a sync queue item in the state machine.
enum SyncQueueItemState: String, Codable, Sendable {
    case pending
    case inProgress
    case completed
    case failed
    case cancelled
}

/// A single item in the local-first sync queue. Persisted via SyncQueueItemEntity.
struct SyncQueueItem: Identifiable, Sendable {
    var id: String
    var kind: SyncQueueItemKind
    var state: SyncQueueItemState
    var attemptCount: Int
    var createdAt: Date
    var updatedAt: Date
    var nextRetryAt: Date?
    var payloadSessionId: String?
    var payloadEventId: String?
    /// Optional JSON or opaque payload for other kinds (e.g. Step 6.5 userProfile).
    var payloadData: Data?

    init(
        id: String,
        kind: SyncQueueItemKind,
        state: SyncQueueItemState,
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
