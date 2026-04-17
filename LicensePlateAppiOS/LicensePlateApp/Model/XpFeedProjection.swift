//
//  XpFeedProjection.swift
//  LicensePlateApp
//
//  Snackbar / feed / recap line derived from ledger rows.
//

import Foundation

enum XpFeedLineState: String, Codable, Sendable, CaseIterable {
    case provisional
    case final
}

struct XpFeedProjection: Identifiable, Sendable, Equatable {
    /// Stable row id (typically `XpLedgerEvent.id`).
    var id: String

    var sourceEventId: String
    var itemId: String
    var title: String
    var subtitle: String?
    var xpDisplayText: String
    var state: XpFeedLineState
    var createdAt: Date
}
