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
    private let bufferCapacity: Int
    private var eventBuffers: [UUID: [DiscoveryChangeEvent]] = [:]

    init(analytics: AnalyticsLogging?, bufferCapacity: Int = 50) {
        self.analytics = analytics
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

        let flags = DiscoverySpamHeuristics.evaluate(foundRegions: foundRegions, recentEvents: buffer)

        if !flags.isEmpty {
            let flagStrings = flags.map(\.rawValue)
            analytics?.log(.riskAdvisoryDetected(flags: flagStrings, tripId: tripId.uuidString))
        }

        return RiskAssessmentResult(flags: flags)
    }
}
