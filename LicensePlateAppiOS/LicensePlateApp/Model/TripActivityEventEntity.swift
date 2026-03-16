//
//  TripActivityEventEntity.swift
//  LicensePlateApp
//
//  Step 01 — SwiftData persistence for TripActivityEvent (append-only gameplay events).
//

import Foundation
import SwiftData

@Model
final class TripActivityEventEntity {
    var id: String
    var sessionId: String
    var kind: String
    var timestamp: Date
    var actorId: String?
    /// JSON-encoded payload (e.g. regionId, gameInstanceId, participantId, inputMethod for region_found/region_removed).
    var payloadData: Data?

    init(
        id: String,
        sessionId: String,
        kind: String,
        timestamp: Date,
        actorId: String? = nil,
        payloadData: Data? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.kind = kind
        self.timestamp = timestamp
        self.actorId = actorId
        self.payloadData = payloadData
    }
}
