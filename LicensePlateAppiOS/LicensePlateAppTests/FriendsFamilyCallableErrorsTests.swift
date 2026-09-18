//
//  FriendsFamilyCallableErrorsTests.swift
//  LicensePlateAppTests
//
//  `FriendsFamilyCallableErrors.map(_:session:)` is a pure function of the error and the
//  session kind, and every mapping test here passes the kind explicitly. The first test used
//  to read the LIVE `Auth.auth().currentUser` inside the test host and flipped with whatever
//  guest the simulator's last `--skipOnboarding` UI run had left in the keychain (observed
//  both ways 2026-09-08..12): with a persisted guest it got the guest copy instead of the
//  recipient copy. Both readings are now pinned on purpose, one per session kind.
//

import Foundation
import FirebaseFunctions
import Testing
@testable import LicensePlateApp

@MainActor
struct FriendsFamilyCallableErrorsTests {

    private func recipientNotRegisteredError() -> NSError {
        NSError(
            domain: FunctionsErrorDomain,
            code: FunctionsErrorCode.failedPrecondition.rawValue,
            userInfo: [
                NSLocalizedDescriptionKey: FriendsFamilyCallableErrors.recipientNotRegisteredServerMessage
            ]
        )
    }

    private func unauthenticatedError() -> NSError {
        NSError(
            domain: FunctionsErrorDomain,
            code: FunctionsErrorCode.unauthenticated.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "User must be authenticated"]
        )
    }

    /// A registered (provider-backed) session: the server's recipient message becomes the
    /// localized recipient copy.
    @Test func mapsRecipientNotRegisteredServerMessage() {
        let mapped = FriendsFamilyCallableErrors.map(
            recipientNotRegisteredError(), session: .credentialed
        ) as NSError
        #expect(mapped.localizedDescription == FriendsFamilyCallableErrors.recipientNotRegisteredMessage)
    }

    /// An anonymous guest: the guest gate wins over the recipient message — the reading the
    /// hosted run produced whenever the simulator held a persisted guest.
    @Test func mapsRecipientNotRegisteredServerMessageToGuestCopyForAnAnonymousSession() {
        let mapped = FriendsFamilyCallableErrors.map(
            recipientNotRegisteredError(), session: .uncredentialed
        ) as NSError
        #expect(mapped.localizedDescription == FriendsFamilyCallableErrors.guestBlockedMessage)
    }

    /// Item 11 (SRS §3.1.1): the FR-84 transferred child holds a custom-token session —
    /// non-anonymous, no provider — and is uncredentialed everywhere else on the client
    /// (`AccountState`, the pre-call gate) and on the server (`assertRegisteredAccount`).
    @Test func classifiesSessionsThroughSessionCredentialPolicy() {
        typealias Kind = FriendsFamilyCallableErrors.SessionKind
        #expect(Kind.classify(isAnonymous: true, providerCount: 0) == .uncredentialed)
        #expect(Kind.classify(isAnonymous: false, providerCount: 0) == .uncredentialed)
        #expect(Kind.classify(isAnonymous: false, providerCount: 1) == .credentialed)
    }

    @Test func mapsUnauthenticatedBySessionKind() {
        let signedOut = FriendsFamilyCallableErrors.map(unauthenticatedError(), session: .signedOut) as NSError
        #expect(signedOut.localizedDescription == "You are not signed in. Sign in and try again.".localized)

        let guest = FriendsFamilyCallableErrors.map(unauthenticatedError(), session: .uncredentialed) as NSError
        #expect(guest.localizedDescription == FriendsFamilyCallableErrors.guestBlockedMessage)

        let registered = FriendsFamilyCallableErrors.map(unauthenticatedError(), session: .credentialed) as NSError
        #expect(registered.localizedDescription == "The server rejected this request. Sign in and try again.".localized)
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
    // non-punitive family copy, never a raw or guest-framed error — and the child branch
    // runs FIRST, so the session kind never changes that answer.
    @Test func mapsChildRestrictionRejectionsToFriendlyCopyForEverySessionKind() {
        let sessions: [FriendsFamilyCallableErrors.SessionKind] = [.signedOut, .uncredentialed, .credentialed]
        for reason in ["unconsented_child", "child_account"] {
            let error = NSError(
                domain: FunctionsErrorDomain,
                code: FunctionsErrorCode.failedPrecondition.rawValue,
                userInfo: [
                    NSLocalizedDescriptionKey: "Guardian consent required",
                    FunctionsErrorDetailsKey: ["reason": reason],
                ]
            )
            for session in sessions {
                let mapped = FriendsFamilyCallableErrors.map(error, session: session) as NSError
                #expect(mapped.localizedDescription == FriendsFamilyCallableErrors.childRestrictionMessage)
            }
        }
    }
}
