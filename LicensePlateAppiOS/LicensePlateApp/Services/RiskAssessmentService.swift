//
//  RiskAssessmentService.swift
//  LicensePlateApp
//
//  Step 11 — Non-blocking advisory risk assessment after discovery changes. Uses DiscoverySpamHeuristics and logs via AnalyticsLogging.
//

import Foundation
import Combine

/// Result of a risk assessment; advisory only, no blocking.
struct RiskAssessmentResult: Sendable {
    var flags: [RiskFlag]
    var shouldShowAdvisory: Bool { !flags.isEmpty }
}

/// Protocol for risk assessment (DI and tests).
@MainActor
protocol RiskAssessing: AnyObject {
    func assessAfterDiscoveryChange(
        tripId: UUID,
        foundRegions: [FoundRegion],
        lastChange: (regionID: String, isAdd: Bool, at: Date)
    ) -> RiskAssessmentResult
}

@MainActor
final class RiskAssessmentService: ObservableObject, RiskAssessing {

    private let analytics: AnalyticsLogging?
    private let heuristics: DiscoverySpamHeuristicsProtocol
    private let bufferCapacity: Int
    private var eventBuffers: [UUID: [DiscoveryChangeEvent]] = [:]

    init(analytics: AnalyticsLogging?, heuristics: DiscoverySpamHeuristicsProtocol = DiscoverySpamHeuristics(), bufferCapacity: Int = 50) {
        self.analytics = analytics
        self.heuristics = heuristics
        self.bufferCapacity = bufferCapacity
    }

    func assessAfterDiscoveryChange(
        tripId: UUID,
        foundRegions: [FoundRegion],
        lastChange: (regionID: String, isAdd: Bool, at: Date)
    ) -> RiskAssessmentResult {
        var buffer = eventBuffers[tripId] ?? []
        buffer.append(DiscoveryChangeEvent(
            date: lastChange.at,
            regionID: lastChange.regionID,
            isAdd: lastChange.isAdd
        ))
        if buffer.count > bufferCapacity {
            buffer = Array(buffer.suffix(bufferCapacity))
        }
        eventBuffers[tripId] = buffer

        let context = buildContext(tripId: tripId, foundRegions: foundRegions, lastChange: lastChange, recentEvents: buffer)
        let flags = heuristics.evaluate(context: context)

        if !flags.isEmpty {
            let flagStrings = flags.map(\.type.rawValue)
            analytics?.log(.riskAdvisoryDetected(flags: flagStrings, tripId: tripId.uuidString))
        }

        return RiskAssessmentResult(flags: flags)
    }

    private func buildContext(
        tripId: UUID,
        foundRegions: [FoundRegion],
        lastChange: (regionID: String, isAdd: Bool, at: Date),
        recentEvents: [DiscoveryChangeEvent]
    ) -> DiscoveryActionContext {
        let ids = foundRegions.map(\.regionID)
        let wasDuplicate = ids.count != Set(ids).count
        let toggleCountForSubject = recentEvents.filter { $0.regionID == lastChange.regionID }.count
        return DiscoveryActionContext(
            participantId: "",
            tripId: tripId,
            subjectId: lastChange.regionID,
            inputMethod: .tap,
            occurredAt: lastChange.at,
            previousDiscoveryTimestamps: recentEvents.filter(\.isAdd).map(\.date),
            recentToggleCount: toggleCountForSubject,
            wasDuplicateCandidate: wasDuplicate,
            foundRegionTimestamps: foundRegions.map(\.foundAt),
            evaluationDate: Date(),
            recentEvents: recentEvents
        )
    }
}
