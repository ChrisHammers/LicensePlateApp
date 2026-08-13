//
//  SyncQueueItem.swift
//  LicensePlateApp
//
//  Step 06 — Domain model for durable sync queue item (state, retry, payload refs).
//

import Foundation

/// State of a sync queue item in the state machine.
///
/// The two terminal give-up states are deliberately distinct, because COPPA FR-28 consent
/// recovery must heal one and must never touch the other:
///
/// - `cancelled` — we gave up, but the SERVER never made a judgement. Its only producer is
///   the transient `game not found` retry cap, which an unconsented child reaches purely
///   because their sessions cannot be published while restricted. This is the recoverable
///   case, and the only one recovery re-enqueues.
/// - `rejected` — the server (or a malformed payload) issued a FINAL VERDICT: invalid
///   argument, permission denied, a non-child failed-precondition such as a discovery that
///   no longer exists. Re-uploading it would push back data the server deliberately refused
///   or deleted (FR-30 retention), so it is terminal and recovery must never resurrect it.
enum SyncQueueItemState: String, Codable, Sendable {
    case pending
    case inProgress
    case completed
    case failed
    /// Gave up without a server verdict — recoverable. See the type doc.
    case cancelled
    /// Server verdict or malformed payload — terminal, never recovered. See the type doc.
    case rejected
    /// Superseded by a recovery re-enqueue: this row's event is live again on a NEW row,
    /// so the old one is settled to keep the recoverable set self-quenching.
    case recovered
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
