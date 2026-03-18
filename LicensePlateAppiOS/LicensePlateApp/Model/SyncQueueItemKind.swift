//
//  SyncQueueItemKind.swift
//  LicensePlateApp
//
//  Step 06 — Kind of sync queue item. Step 6.5 will add userProfile.
//

import Foundation

/// Kind of item in the sync queue. Step 6.5 will add other kinds (e.g. userProfile).
enum SyncQueueItemKind: String, Codable, CaseIterable, Sendable {
    case gameplayEvent = "gameplay_event"
    case userProfile = "user_profile"
}
