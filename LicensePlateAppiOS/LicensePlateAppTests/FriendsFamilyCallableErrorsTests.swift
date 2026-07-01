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
}
