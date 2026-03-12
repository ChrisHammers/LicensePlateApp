//
//  DiscoveryActionContext.swift
//  LicensePlateApp
//
//  Step 11 expected structure — Rich context for heuristics (participant, timestamps, toggles, location).
//

import Foundation

/// A single discovery change (add or remove) for heuristics input.
struct DiscoveryChangeEvent: Sendable, Equatable {
    var date: Date
    var regionID: String
    var isAdd: Bool
}

enum DiscoveryInputMethod: String, Codable, Sendable {
    case tap
    case voice
    case syncReplay
    case futureCamera

    static func from(_ method: FoundRegion.InputMethod) -> DiscoveryInputMethod {
        switch method {
        case .list: return .tap
        case .voice: return .voice
        }
    }
}

struct DiscoveryActionContext: Sendable, Equatable {
    var participantId: String
    var gameInstanceId: UUID?
    var tripId: UUID
    var subjectId: String
    var inputMethod: DiscoveryInputMethod
    var occurredAt: Date

    var previousDiscoveryTimestamps: [Date]
    var recentToggleCount: Int
    var wasDuplicateCandidate: Bool

    var locationTimestamp: Date?
    var locationDistanceFromPreviousMeters: Double?

    /// Timestamps of current found regions (for impossible-timestamp heuristic).
    var foundRegionTimestamps: [Date]
    /// Evaluation time (e.g. now) for timestamp bounds.
    var evaluationDate: Date
    /// Recent change events (for burst, rapid loop, toggle heuristics). Use DiscoveryChangeEvent from DiscoverySpamHeuristics.
    var recentEvents: [DiscoveryChangeEvent]

    init(
        participantId: String,
        gameInstanceId: UUID? = nil,
        tripId: UUID,
        subjectId: String,
        inputMethod: DiscoveryInputMethod,
        occurredAt: Date = Date(),
        previousDiscoveryTimestamps: [Date] = [],
        recentToggleCount: Int = 0,
        wasDuplicateCandidate: Bool = false,
        locationTimestamp: Date? = nil,
        locationDistanceFromPreviousMeters: Double? = nil,
        foundRegionTimestamps: [Date] = [],
        evaluationDate: Date = Date(),
        recentEvents: [DiscoveryChangeEvent] = []
    ) {
        self.participantId = participantId
        self.gameInstanceId = gameInstanceId
        self.tripId = tripId
        self.subjectId = subjectId
        self.inputMethod = inputMethod
        self.occurredAt = occurredAt
        self.previousDiscoveryTimestamps = previousDiscoveryTimestamps
        self.recentToggleCount = recentToggleCount
        self.wasDuplicateCandidate = wasDuplicateCandidate
        self.locationTimestamp = locationTimestamp
        self.locationDistanceFromPreviousMeters = locationDistanceFromPreviousMeters
        self.foundRegionTimestamps = foundRegionTimestamps
        self.evaluationDate = evaluationDate
        self.recentEvents = recentEvents
    }
}
