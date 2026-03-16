//
//  TripSessionEntity.swift
//  LicensePlateApp
//
//  SwiftData persistence for the new gameplay trip/session model.
//

import Foundation
import SwiftData

/// Persisted trip session for the gameplay model. Use with TripSession (domain) via mapper.
@Model
final class TripSessionEntity {
    var id: String
    var name: String
    var status: String
    var mode: String
    var createdAt: Date?
    var createdBy: String?
    var startedAt: Date?
    var endedAt: Date?
    var endedBy: String?
    /// Comma-separated country raw values (e.g. "United States,Canada,Mexico").
    var enabledCountryRawValues: String
    /// Encoded [TripParticipant] (JSON); optional for migration.
    var participantsData: Data?

    init(
        id: String,
        name: String,
        status: String,
        mode: String,
        createdAt: Date? = nil,
        createdBy: String? = nil,
        startedAt: Date? = nil,
        endedAt: Date? = nil,
        endedBy: String? = nil,
        enabledCountryRawValues: String = "United States,Canada,Mexico",
        participantsData: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.mode = mode
        self.createdAt = createdAt
        self.createdBy = createdBy
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.endedBy = endedBy
        self.enabledCountryRawValues = enabledCountryRawValues
        self.participantsData = participantsData
    }
}
