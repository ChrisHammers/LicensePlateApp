//
//  FriendsFamilyCallableErrorsTests.swift
//  LicensePlateAppTests
//

import Foundation
import FirebaseFunctions
import Testing
@testable import LicensePlateApp

struct FriendsFamilyCallableErrorsTests {

    @Test func mapsRecipientNotRegisteredServerMessage() {
        let error = NSError(
            domain: FunctionsErrorDomain,
            code: FunctionsErrorCode.failedPrecondition.rawValue,
            userInfo: [
                NSLocalizedDescriptionKey: FriendsFamilyCallableErrors.recipientNotRegisteredServerMessage
            ]
        )

        let mapped = FriendsFamilyCallableErrors.map(error) as NSError
        #expect(mapped.localizedDescription == FriendsFamilyCallableErrors.recipientNotRegisteredMessage)
    }

    @Test func passesThroughUnrelatedErrors() {
        let error = NSError(
            domain: "ExampleDomain",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: "Something else"]
        )

        let mapped = FriendsFamilyCallableErrors.map(error) as NSError
        #expect(mapped.domain == "ExampleDomain")
        #expect(mapped.code == 42)
    }

    // COPPA F-6 (FR-28): server unconsented-child/child-account rejections map to the
    // non-punitive family copy, never a raw or guest-framed error.
    @Test func mapsChildRestrictionRejectionsToFriendlyCopy() {
        for reason in ["unconsented_child", "child_account"] {
            let error = NSError(
                domain: FunctionsErrorDomain,
                code: FunctionsErrorCode.failedPrecondition.rawValue,
                userInfo: [
                    NSLocalizedDescriptionKey: "Guardian consent required",
                    FunctionsErrorDetailsKey: ["reason": reason],
                ]
            )
            let mapped = FriendsFamilyCallableErrors.map(error) as NSError
            #expect(mapped.localizedDescription == FriendsFamilyCallableErrors.childRestrictionMessage)
        }
    }
}
