//
//  MockRiskAssessmentService.swift
//  LicensePlateAppTests
//
//  Step 13 — Test double for RiskAssessing. Configurable result; no singletons.
//

import Foundation
@testable import LicensePlateApp

@MainActor
final class MockRiskAssessmentService: RiskAssessing {
    var resultToReturn: RiskAssessmentResult = RiskAssessmentResult(flags: [])
    var assessCallCount = 0

    func assessAfterDiscoveryChange(
        tripId: UUID,
        foundRegions: [FoundRegion],
        lastChange: (regionID: String, isAdd: Bool, at: Date)
    ) -> RiskAssessmentResult {
        assessCallCount += 1
        return resultToReturn
    }
}
