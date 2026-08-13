//
//  MockFamilyChildStatusService.swift
//  LicensePlateAppTests
//
//  COPPA F-8 — records child-status callable invocations so view-model flows can be
//  driven end to end without Firebase. No singletons.
//

import Foundation
@testable import LicensePlateApp

@MainActor
final class MockFamilyChildStatusService: FamilyChildStatusManaging {
    struct SetChildStatusCall: Equatable {
        var familyId: String
        var memberUserId: String
        var isChild: Bool
        var consentAcknowledged: Bool
        var guardianAffirmed: Bool
        var correctionReason: ChildStatusCorrectionReason?
        var expectedAgeOutYear: Int?
    }

    struct DeletionCall: Equatable {
        var familyId: String
        var childUserId: String
    }

    private(set) var setChildStatusCalls: [SetChildStatusCall] = []
    private(set) var deletionCalls: [DeletionCall] = []
    private(set) var consentStatusCalls: [DeletionCall] = []

    var setChildStatusError: Error?
    var deletionError: Error?
    var consentStatusError: Error?
    var consentStatusResult = ParentalConsentStatus(records: [])

    func setChildStatus(
        familyId: String,
        memberUserId: String,
        isChild: Bool,
        consentAcknowledged: Bool,
        guardianAffirmed: Bool,
        correctionReason: ChildStatusCorrectionReason?,
        expectedAgeOutYear: Int?
    ) async throws {
        setChildStatusCalls.append(
            SetChildStatusCall(
                familyId: familyId,
                memberUserId: memberUserId,
                isChild: isChild,
                consentAcknowledged: consentAcknowledged,
                guardianAffirmed: guardianAffirmed,
                correctionReason: correctionReason,
                expectedAgeOutYear: expectedAgeOutYear
            )
        )
        if let setChildStatusError { throw setChildStatusError }
    }

    func requestChildDataDeletion(familyId: String, childUserId: String) async throws {
        deletionCalls.append(DeletionCall(familyId: familyId, childUserId: childUserId))
        if let deletionError { throw deletionError }
    }

    func getParentalConsentStatus(
        familyId: String,
        childUserId: String
    ) async throws -> ParentalConsentStatus {
        consentStatusCalls.append(DeletionCall(familyId: familyId, childUserId: childUserId))
        if let consentStatusError { throw consentStatusError }
        return consentStatusResult
    }
}
