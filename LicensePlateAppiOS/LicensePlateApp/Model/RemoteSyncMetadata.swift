//
//  RemoteSyncMetadata.swift
//  LicensePlateApp
//
//  Step 06 — Key-value metadata for "last synced" cursors (session, user, etc.). Step 6.5 can use keys like "user:userId".
//

import Foundation
import SwiftData

/// Domain model for remote sync cursor / metadata (e.g. last synced at per session or user).
struct RemoteSyncMetadata: Sendable {
    var key: String
    var lastSyncedAt: Date?
    var valueData: Data?

    init(key: String, lastSyncedAt: Date? = nil, valueData: Data? = nil) {
        self.key = key
        self.lastSyncedAt = lastSyncedAt
        self.valueData = valueData
    }
}

/// SwiftData entity for RemoteSyncMetadata (unique key).
@Model
final class RemoteSyncMetadataEntity {
    @Attribute(.unique) var key: String
    var lastSyncedAt: Date?
    var valueData: Data?

    init(key: String, lastSyncedAt: Date? = nil, valueData: Data? = nil) {
        self.key = key
        self.lastSyncedAt = lastSyncedAt
        self.valueData = valueData
    }
}
