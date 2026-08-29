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
        var expectedAgeOutYearMonth: Int?
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
        expectedAgeOutYearMonth: Int?
    ) async throws {
        setChildStatusCalls.append(
            SetChildStatusCall(
                familyId: familyId,
                memberUserId: memberUserId,
                isChild: isChild,
                consentAcknowledged: consentAcknowledged,
                guardianAffirmed: guardianAffirmed,
                correctionReason: correctionReason,
                expectedAgeOutYearMonth: expectedAgeOutYearMonth
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

    private(set) var inventoryCalls: [DeletionCall] = []
    var inventoryError: Error?
    var inventoryResult: ChildDataInventory? = ChildDataInventory(
        accountExists: true,
        viaGuardianship: false,
        generatedAt: nil
    )

    func getChildDataInventory(
        familyId: String,
        childUserId: String
    ) async throws -> ChildDataInventory? {
        inventoryCalls.append(DeletionCall(familyId: familyId, childUserId: childUserId))
        if let inventoryError { throw inventoryError }
        return inventoryResult
    }

    private(set) var listGuardedChildrenCallCount = 0
    var guardedChildrenError: Error?
    var guardedChildrenResult: [GuardedChildSummary] = []

    func listGuardedChildren() async throws -> [GuardedChildSummary] {
        listGuardedChildrenCallCount += 1
        if let guardedChildrenError { throw guardedChildrenError }
        return guardedChildrenResult
    }
}
