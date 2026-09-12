//
//  FR84DeviceTransferAdoptionTests.swift
//  LicensePlateAppTests
//
//  COPPA v3 FR-84 (F-41) — parent-initiated device transfer, CLIENT side.
//
//  The server half of this feature is pinned in `functions/src/deviceTransfer.test.ts`. What
//  cannot be pinned there is the hazard that makes the client half interesting: the receiving
//  device already runs two protective mechanisms that are, by construction, indistinguishable
//  from an attack on exactly the state a transfer creates.
//
//   - `RestoredIdentityAgeAnswerPolicy` detaches an anonymous session that the current under-13
//     answer does not own — built for a Keychain-restored stranger's session after a reinstall
//     (§3.1.1 items 5/8). A transferred identity presents that EXACT shape: an
//     anonymous-equivalent session, an under-13 answer, and a uid this epoch never provisioned.
//     Its detach reason is the ONLY one that also discards the inherited profile, so a transfer
//     that skipped the bookkeeping would undo itself on the next launch AND take the child's
//     username and avatar with it — after the single-use code had already been spent.
//   - `detachedIdentityUserIds` is a one-way ratchet, and `loadUserFromFirebase` refuses any uid
//     in it outright. The devices most likely to need a transfer are precisely the ones that
//     have detached an identity before.
//
//  So the tests below are less about the new code than about the OLD code's reaction to it.
//  `theAdoptedIdentityIsNotDetachedOnTheNextLaunch` is the one that matters most: it composes
//  the two policies and asserts the composition, which is where the bug would actually live.
//

import Foundation
import Testing
@testable import LicensePlateApp

@MainActor
struct DeviceTransferAdoptionPolicyTests {

    // MARK: - The plan

    @Test func aFreshChildDeviceOnlyNeedsTheDeclaredMark() {
        let plan = DeviceTransferAdoptionPolicy.adoption(
            currentCategory: .under13,
            isIdentityDetached: false,
            isAlreadyDeclaredChild: false
        )
        #expect(plan.recordsUnder13Answer == false)
        #expect(plan.releasesDetachRatchet == false)
        #expect(plan.marksDeclaredChild == true)
        #expect(plan.isNoOp == false)
    }

    /// The adult-answered device: a parent sets the new tablet up themselves, or the child
    /// tapped 13+ before the code arrived. The device is about to host a child's account, so
    /// the protective answer has to become true here — this is where "no adult leakage" is
    /// decided. The answer is DERIVED from the server's consented-child fact rather than asked
    /// again, which is what FR-84 means by not re-asking the age question.
    @Test func anAdultAnsweredDeviceRecordsTheUnder13AnswerItself() {
        let plan = DeviceTransferAdoptionPolicy.adoption(
            currentCategory: .teenAdult,
            isIdentityDetached: false,
            isAlreadyDeclaredChild: false
        )
        #expect(plan.recordsUnder13Answer == true)
    }

    @Test func anUnansweredDeviceAlsoRecordsTheUnder13Answer() {
        let plan = DeviceTransferAdoptionPolicy.adoption(
            currentCategory: nil,
            isIdentityDetached: false,
            isAlreadyDeclaredChild: false
        )
        #expect(plan.recordsUnder13Answer == true)
    }

    /// The §3.1.1 items 5/7/8 population — the likeliest transfer recipient of all.
    @Test func aPreviouslyDetachedUidReleasesTheRatchet() {
        let plan = DeviceTransferAdoptionPolicy.adoption(
            currentCategory: .under13,
            isIdentityDetached: true,
            isAlreadyDeclaredChild: false
        )
        #expect(plan.releasesDetachRatchet == true)
    }

    @Test func aFullyRecordedAdoptionIsANoOp() {
        let plan = DeviceTransferAdoptionPolicy.adoption(
            currentCategory: .under13,
            isIdentityDetached: false,
            isAlreadyDeclaredChild: true
        )
        #expect(plan.isNoOp)
    }

    // MARK: - mayAdopt

    @Test func adoptingTheSessionYouAreAlreadyRunningIsRefused() {
        #expect(
            DeviceTransferAdoptionPolicy.mayAdopt(transferredUserId: "kid", currentUserId: "kid")
                == false
        )
        #expect(DeviceTransferAdoptionPolicy.mayAdopt(transferredUserId: "", currentUserId: nil) == false)
        #expect(DeviceTransferAdoptionPolicy.mayAdopt(transferredUserId: "kid", currentUserId: nil))
        #expect(
            DeviceTransferAdoptionPolicy.mayAdopt(transferredUserId: "kid", currentUserId: "throwaway")
        )
    }
}

@MainActor
struct DeviceTransferAgeGateStoreTests {

    private func makeStore(
        suite: String = "DeviceTransferAgeGateStoreTests-\(UUID().uuidString)"
    ) -> (AgeGateStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (AgeGateStore(defaults: defaults), defaults)
    }

    // MARK: - The composed invariant this whole file exists for

    /// The regression lock. If the adoption stops landing the uid in `declaredChildUserIds`,
    /// the next launch runs `RestoredIdentityAgeAnswerPolicy` over a session that looks exactly
    /// like a restored stranger's, detaches it with the one reason that ALSO wipes the profile,
    /// and the transfer silently undoes itself — with the code already spent.
    @Test func theAdoptedIdentityIsNotDetachedOnTheNextLaunch() {
        let (store, _) = makeStore()
        store.recordAnswer(.under13)

        // Before adoption: this is precisely the shape the detach policy fires on.
        #expect(
            RestoredIdentityAgeAnswerPolicy.requiresLocalDetach(
                category: store.category,
                isAnonymousSession: true,
                isBoundToCurrentAnswer: store.isPendingDeclaration(userId: "kid")
                    || store.isDeclaredChildUserId("kid")
            )
        )

        store.adoptTransferredChildIdentity(userId: "kid")

        #expect(
            RestoredIdentityAgeAnswerPolicy.requiresLocalDetach(
                category: store.category,
                isAnonymousSession: true,
                isBoundToCurrentAnswer: store.isPendingDeclaration(userId: "kid")
                    || store.isDeclaredChildUserId("kid")
            ) == false
        )
    }

    // MARK: - What the adoption writes

    @Test func adoptionMarksTheUidDeclaredWithoutLeavingItPending() {
        let (store, _) = makeStore()
        store.recordAnswer(.under13)

        store.adoptTransferredChildIdentity(userId: "kid")

        // DECLARED, not pending: the account was declared long ago, server-side. A pending
        // entry would make `hasOutstandingChildDeclaration` true and hold every profile write
        // behind a declaration that will never be sent.
        #expect(store.isDeclaredChildUserId("kid"))
        #expect(store.isPendingDeclaration(userId: "kid") == false)
        #expect(store.hasOutstandingChildDeclaration == false)
    }

    /// No adult leakage: a device that answered 13+ ends up carrying the child answer, because
    /// it is now hosting a child's account and every client-side hold reads that answer.
    @Test func adoptionOnAnAdultAnsweredDeviceRecordsTheChildAnswer() {
        let (store, _) = makeStore()
        store.recordAnswer(.teenAdult)
        #expect(store.category == .teenAdult)

        store.adoptTransferredChildIdentity(userId: "kid")

        #expect(store.category == .under13)
        #expect(store.isDeclaredChildUserId("kid"))
    }

    @Test func adoptionOnAnUnansweredDeviceRecordsTheChildAnswer() {
        let (store, _) = makeStore()
        #expect(store.category == nil)

        store.adoptTransferredChildIdentity(userId: "kid")

        #expect(store.category == .under13)
        #expect(store.isDeclaredChildUserId("kid"))
    }

    // MARK: - The ratchet release

    @Test func adoptionReleasesADetachedUidSoTheBootstrapWillHydrateIt() {
        let (store, _) = makeStore()
        store.recordAnswer(.under13)
        store.markIdentityDetached(userId: "kid")
        #expect(store.isIdentityDetached("kid"))

        store.adoptTransferredChildIdentity(userId: "kid")

        #expect(store.isIdentityDetached("kid") == false)
    }

    /// The release is surgical. Every OTHER retired identity on this device stays retired —
    /// a transfer says something about one uid, and nothing about any other.
    @Test func theReleaseTouchesOnlyTheAdoptedUid() {
        let (store, _) = makeStore()
        store.recordAnswer(.under13)
        store.markIdentityDetached(userId: "kid")
        store.markIdentityDetached(userId: "someOtherDeadUid")

        store.adoptTransferredChildIdentity(userId: "kid")

        #expect(store.isIdentityDetached("kid") == false)
        #expect(store.isIdentityDetached("someOtherDeadUid"))
    }

    /// The ratchet is still a ratchet for everything that is not a transfer: nothing else in
    /// the app can reach `releaseDetachedIdentityAfterTransfer`, and re-marking still sticks.
    @Test func theRatchetStillHoldsAfterATransferOfADifferentUid() {
        let (store, _) = makeStore()
        store.recordAnswer(.under13)
        store.markIdentityDetached(userId: "deadUid")

        store.adoptTransferredChildIdentity(userId: "kid")
        store.markIdentityDetached(userId: "deadUid")

        #expect(store.isIdentityDetached("deadUid"))
    }

    // MARK: - Idempotence and guards

    @Test func adoptingTwiceIsANoOpTheSecondTime() {
        let (store, _) = makeStore()
        store.recordAnswer(.under13)
        store.adoptTransferredChildIdentity(userId: "kid")
        let revisionAfterFirst = store.revision

        store.adoptTransferredChildIdentity(userId: "kid")

        #expect(store.revision == revisionAfterFirst)
        #expect(store.isDeclaredChildUserId("kid"))
    }

    @Test func anEmptyUidWritesNothing() {
        let (store, _) = makeStore()
        let revisionBefore = store.revision

        store.adoptTransferredChildIdentity(userId: "")

        #expect(store.revision == revisionBefore)
        #expect(store.category == nil)
    }

    /// The adoption survives the state changes that follow a transfer. `clearAnswer()` runs on
    /// every sign-out path and drops the epoch answer, but the uid-bound declared history is
    /// what the child holds survive on — so a transferred child who is later signed out is
    /// still a child this device knows about.
    @Test func theDeclaredHistorySurvivesAClearedAnswer() {
        let (store, _) = makeStore()
        store.adoptTransferredChildIdentity(userId: "kid")

        store.clearAnswer()

        #expect(store.isDeclaredChildUserId("kid"))
        #expect(store.hasDeclaredChildHistory)
    }
}
