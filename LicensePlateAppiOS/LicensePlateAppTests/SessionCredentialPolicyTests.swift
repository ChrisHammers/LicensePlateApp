//
//  SessionCredentialPolicyTests.swift
//  LicensePlateAppTests
//
//  Item 11 of SRS 3.1.1 (owner device tests 2026-09-11): a transferred child signs in with a
//  CUSTOM token — non-anonymous, no provider — and every client site that equated "registered"
//  with `!isAnonymous` read them as a Signed-In adult: registered controls on the child's
//  profile, the child's account offered as a "saved user" after a reinstall, the anonymous-only
//  zombie guards skipping them. One predicate now draws the line the rules already draw
//  (`isRegisteredAccount()` excludes anonymous AND custom).
//

import Foundation
import Testing
@testable import LicensePlateApp

struct SessionCredentialPolicyTests {

    @Test func anAnonymousSessionIsNotCredentialed() {
        #expect(!SessionCredentialPolicy.isCredentialed(isAnonymous: true, providerCount: 0))
    }

    @Test func aCustomTokenSessionIsNotCredentialed() {
        // The FR-84 transferred child: `isAnonymous == false`, `providerData` empty.
        #expect(!SessionCredentialPolicy.isCredentialed(isAnonymous: false, providerCount: 0))
    }

    @Test func aProviderBackedSessionIsCredentialed() {
        #expect(SessionCredentialPolicy.isCredentialed(isAnonymous: false, providerCount: 1))
        #expect(SessionCredentialPolicy.isCredentialed(isAnonymous: false, providerCount: 2))
    }
}

@MainActor
struct TransferredChildAuthenticationStatusTests {

    /// The exact input shape a transferred child produces once the service derives its flags
    /// from `SessionCredentialPolicy`: not a registered session, anonymous-EQUIVALENT, a uid,
    /// and the one child classification. It must land on the child state — never on
    /// `.registeredAdult`, which is what showed Sign Out / Delete Account / "Set up this
    /// device for a child" to a child.
    @Test func aTransferredConsentedChildIsAConsentedChildNotASignedInAdult() {
        let state = AuthenticationStatusPolicy.state(for: .init(
            isRegisteredSession: false,
            wasPreviouslySignedIn: false,
            isAnonymousSession: true,
            hasFirebaseUid: true,
            childSessionState: .consentedChild
        ))
        #expect(state == .consentedChild)
    }

    @Test func aProviderBackedAdultStillReadsAsRegistered() {
        let state = AuthenticationStatusPolicy.state(for: .init(
            isRegisteredSession: true,
            hasFirebaseUid: true
        ))
        #expect(state == .registeredAdult)
    }
}

struct GuestContinuationOverCustomTokenTests {

    @Test func continueAsGuestOverARestoredTransferredChildMintsAFreshSession() {
        #expect(GuestContinuationPolicy.shouldCreateFreshAnonymousSession(
            accountState: .firebaseAnonymous, isCustomTokenSession: true
        ))
    }

    @Test func aRestoredAnonymousGuestIsStillKept() {
        // Owner ruling 2026-09-07: a restored anonymous guest keeps its uid.
        #expect(!GuestContinuationPolicy.shouldCreateFreshAnonymousSession(
            accountState: .firebaseAnonymous, isCustomTokenSession: false
        ))
    }

    @Test func aSignedInAdultStillGetsAFreshSessionWhenContinuingAsGuest() {
        #expect(GuestContinuationPolicy.shouldCreateFreshAnonymousSession(accountState: .signedIn))
    }
}

struct SavedAccountOfferPolicyTests {

    @Test func aCredentialedAdultSessionIsOfferedUnderAnAdultOrNoAnswer() {
        #expect(SavedAccountOfferPolicy.mayOfferRestoredAccount(isCredentialedSession: true, deviceAnswer: .teenAdult))
        #expect(SavedAccountOfferPolicy.mayOfferRestoredAccount(isCredentialedSession: true, deviceAnswer: nil))
    }

    @Test func nothingIsOfferedUnderAnUnder13Answer() {
        // Owner 2026-09-12: a child date must not surface the adult's saved account.
        #expect(!SavedAccountOfferPolicy.mayOfferRestoredAccount(isCredentialedSession: true, deviceAnswer: .under13))
    }

    @Test func anUncredentialedSessionIsNeverOffered() {
        // Anonymous guest or transferred child (custom token): not anybody's to "continue as".
        #expect(!SavedAccountOfferPolicy.mayOfferRestoredAccount(isCredentialedSession: false, deviceAnswer: .teenAdult))
        #expect(!SavedAccountOfferPolicy.mayOfferRestoredAccount(isCredentialedSession: false, deviceAnswer: nil))
    }
}
