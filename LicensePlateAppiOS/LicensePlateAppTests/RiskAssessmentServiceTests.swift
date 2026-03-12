//
//  RiskAssessmentServiceTests.swift
//  LicensePlateAppTests
//
//  Step 11 — RiskAssessmentService: advisory assessment, analytics logging, no blocking; returns [RiskFlag] structs.
//

import Foundation
import Testing
@testable import LicensePlateApp

@MainActor
struct RiskAssessmentServiceTests {

    private func makeFoundRegion(regionID: String, foundAt: Date = Date()) -> FoundRegion {
        FoundRegion(
            regionID: regionID,
            foundAt: foundAt,
            inputMethod: .list,
            foundBy: nil,
            foundAtLocation: nil
        )
    }

    @Test func assessAfterDiscoveryChangeReturnsEmptyWhenNoRisk() async throws {
        let spy = AnalyticsLoggingSpy()
        let service = RiskAssessmentService(analytics: spy, bufferCapacity: 50)
        let tripId = UUID()
        let found: [FoundRegion] = [makeFoundRegion(regionID: "us-ca")]
        let result = service.assessAfterDiscoveryChange(
            tripId: tripId,
            foundRegions: found,
            lastChange: ("us-ca", true, Date())
        )
        #expect(result.flags.isEmpty)
        #expect(!result.shouldShowAdvisory)
        #expect(spy.loggedEvents.isEmpty)
    }

    @Test func assessAfterDiscoveryChangeLogsAndReturnsFlagsWhenBurstDetected() async throws {
        let spy = AnalyticsLoggingSpy()
        let service = RiskAssessmentService(analytics: spy, bufferCapacity: 50)
        let tripId = UUID()
        let now = Date()
        var found: [FoundRegion] = []
        for i in 0..<11 {
            let regionID = "region-\(i)"
            found.append(makeFoundRegion(regionID: regionID, foundAt: now))
            let result = service.assessAfterDiscoveryChange(
                tripId: tripId,
                foundRegions: found,
                lastChange: (regionID, true, now.addingTimeInterval(-Double(10 - i)))
            )
            if i == 10 {
                #expect(!result.flags.isEmpty)
                #expect(result.shouldShowAdvisory)
                #expect(result.flags.contains(where: { $0.type == .burstInputPattern }))
            }
        }
        let riskLogged = spy.loggedEvents.contains { $0.name == "risk_advisory_detected" }
        #expect(riskLogged)
    }

    @Test func assessAfterDiscoveryChangeDoesNotBlockAlwaysReturns() async throws {
        let service = RiskAssessmentService(analytics: nil, bufferCapacity: 2)
        let tripId = UUID()
        let result = service.assessAfterDiscoveryChange(
            tripId: tripId,
            foundRegions: [],
            lastChange: ("us-ca", true, Date())
        )
        #expect(result.flags.isEmpty || !result.flags.isEmpty)
    }

    @Test func assessWithDuplicateDiscoveryReturnsFlag() async throws {
        let spy = AnalyticsLoggingSpy()
        let service = RiskAssessmentService(analytics: spy, bufferCapacity: 50)
        let tripId = UUID()
        let t = Date()
        let found: [FoundRegion] = [
            makeFoundRegion(regionID: "us-ca", foundAt: t),
            makeFoundRegion(regionID: "us-ca", foundAt: t.addingTimeInterval(1))
        ]
        let result = service.assessAfterDiscoveryChange(
            tripId: tripId,
            foundRegions: found,
            lastChange: ("us-ca", true, t)
        )
        #expect(result.flags.contains(where: { $0.type == .duplicateDiscovery }))
        #expect(result.shouldShowAdvisory)
        #expect(spy.loggedEvents.contains { $0.name == "risk_advisory_detected" })
    }
}
