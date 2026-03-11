//
//  TripSession.swift
//  LicensePlateApp
//
//  Gameplay model foundation — new trip/session entity shape (SwiftData-ready; no @Model in Step 01).
//

import Foundation

/// Represents a trip in the new gameplay model. Supports solo, collaborative, and competitive modes.
/// Optional `legacyTripId` links to a legacy `Trip` when adapted from existing data.
final class TripSession {
    var id: UUID
    var name: String
    var status: TripStatus
    var mode: TripMode
    var createdBy: String?
    var startedAt: Date?
    var endedAt: Date?
    var endedBy: String?
    /// Snapshot of participants (e.g. for display); can be derived from events or stored.
    var participants: [TripParticipant]
    /// Optional teams for this session (e.g. for team-based scoring). Empty when not using teams.
    var teams: [TripTeam]
    /// When non-nil, this session was built from or backs the legacy Trip with this id.
    var legacyTripId: UUID?
    /// Enabled countries for this trip (e.g. US, Canada, Mexico).
    var enabledCountryRawValues: [String]
    /// Optional location/risk flags for future anti-spam.
    var riskFlags: [String]?

    init(
        id: UUID = UUID(),
        name: String,
        status: TripStatus = .draft,
        mode: TripMode = .solo,
        createdBy: String? = nil,
        startedAt: Date? = nil,
        endedAt: Date? = nil,
        endedBy: String? = nil,
        participants: [TripParticipant] = [],
        teams: [TripTeam] = [],
        legacyTripId: UUID? = nil,
        enabledCountryRawValues: [String] = ["United States", "Canada", "Mexico"],
        riskFlags: [String]? = nil
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.mode = mode
        self.createdBy = createdBy
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.endedBy = endedBy
        self.participants = participants
        self.teams = teams
        self.legacyTripId = legacyTripId
        self.enabledCountryRawValues = enabledCountryRawValues
        self.riskFlags = riskFlags
    }

    /// Enabled countries as enum values when using PlateRegion.Country.
    var enabledCountries: [PlateRegion.Country] {
        get {
            enabledCountryRawValues.compactMap { PlateRegion.Country(rawValue: $0) }
        }
        set {
            enabledCountryRawValues = newValue.map { $0.rawValue }
        }
    }
}
