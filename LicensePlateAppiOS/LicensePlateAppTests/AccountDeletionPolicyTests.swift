//
//  AccountDeletionPolicyTests.swift
//  LicensePlateAppTests
//
//  Pure policy for the in-app account deletion flow (Guideline 5.1.1(v)):
//  re-auth option mapping and server error classification.
//

import Foundation
import FirebaseFunctions
import Testing
@testable import LicensePlateApp

struct AccountDeletionPolicyTests {

    // MARK: - Re-auth method mapping

    @Test func reauthMethodsMapLinkedProvidersInPresentationOrder() {
        let methods = AccountDeletionPolicy.reauthMethods(
            forProviderIDs: ["password", "google.com", "apple.com"]
        )
        #expect(methods == [.apple, .google, .emailPassword])
    }

    @Test func reauthMethodsForPasswordOnlyAccount() {
        let methods = AccountDeletionPolicy.reauthMethods(forProviderIDs: ["password"])
        #expect(methods == [.emailPassword])
    }

    @Test func reauthMethodsDropUnknownProvidersAndDuplicates() {
        let methods = AccountDeletionPolicy.reauthMethods(
            forProviderIDs: ["facebook.com", "google.com", "google.com", "yahoo.com"]
        )
        #expect(methods == [.google])
    }

    @Test func reauthMethodsAreEmptyWhenSignedOut() {
        #expect(AccountDeletionPolicy.reauthMethods(forProviderIDs: []).isEmpty)
    }

    // MARK: - Recent-login detection

    @Test func recentLoginRequiredMatchesServerSignal() {
        #expect(
            AccountDeletionPolicy.isRecentLoginRequired(
                domain: FunctionsErrorDomain,
                code: FunctionsErrorCode.failedPrecondition.rawValue,
                detailsReason: "recent-login-required"
            )
        )
    }

    @Test func recentLoginRequiredRejectsOtherFailedPreconditions() {
        // e.g. the anonymous-account gate also uses failed-precondition but no reason.
        #expect(
            !AccountDeletionPolicy.isRecentLoginRequired(
                domain: FunctionsErrorDomain,
                code: FunctionsErrorCode.failedPrecondition.rawValue,
                detailsReason: nil
            )
        )
    }

    @Test func recentLoginRequiredRejectsOtherDomainsAndCodes() {
        #expect(
            !AccountDeletionPolicy.isRecentLoginRequired(
                domain: "SomeOtherDomain",
                code: FunctionsErrorCode.failedPrecondition.rawValue,
                detailsReason: "recent-login-required"
            )
        )
        #expect(
            !AccountDeletionPolicy.isRecentLoginRequired(
                domain: FunctionsErrorDomain,
                code: FunctionsErrorCode.permissionDenied.rawValue,
                detailsReason: "recent-login-required"
            )
        )
    }

    // MARK: - Server error classification

    @Test func classifyServerErrorMapsRecentLoginRequired() {
        let error = AccountDeletionPolicy.classifyServerError(
            domain: FunctionsErrorDomain,
            code: FunctionsErrorCode.failedPrecondition.rawValue,
            detailsReason: "recent-login-required",
            message: "Recent sign-in is required to delete your account"
        )
        #expect(error == .recentLoginRequired)
    }

    @Test func classifyServerErrorMapsUnavailableToOffline() {
        let error = AccountDeletionPolicy.classifyServerError(
            domain: FunctionsErrorDomain,
            code: FunctionsErrorCode.unavailable.rawValue,
            detailsReason: nil,
            message: "unavailable"
        )
        #expect(error == .offline)
    }

    @Test func classifyServerErrorFallsBackToServerErrorWithMessage() {
        let error = AccountDeletionPolicy.classifyServerError(
            domain: FunctionsErrorDomain,
            code: FunctionsErrorCode.internal.rawValue,
            detailsReason: nil,
            message: "boom"
        )
        #expect(error == .serverError("boom"))
    }

    @Test func mapServerErrorReadsFunctionsDetailsPayload() {
        let nsError = NSError(
            domain: FunctionsErrorDomain,
            code: FunctionsErrorCode.failedPrecondition.rawValue,
            userInfo: [
                FunctionsErrorDetailsKey: ["reason": "recent-login-required"],
                NSLocalizedDescriptionKey: "Recent sign-in is required to delete your account",
            ]
        )
        #expect(AccountDeletionService.mapServerError(nsError) == .recentLoginRequired)
    }

    @Test func mapServerErrorPassesThroughUnknownFailuresAsServerError() {
        let nsError = NSError(
            domain: FunctionsErrorDomain,
            code: FunctionsErrorCode.internal.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "INTERNAL"]
        )
        #expect(AccountDeletionService.mapServerError(nsError) == .serverError("INTERNAL"))
    }
}
