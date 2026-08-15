//
//  FR60LocalFirstChildTests.swift
//  LicensePlateAppTests
//
//  COPPA F-18 (FR-60) — an unconsented child has no backend identity at all.
//
//  The model these tests defend: an under-13 answer records the epoch's obligation and
//  nothing else. No anonymous uid, no `users/{uid}`, no `declareChildRegistration` at
//  answer time. The child plays fully locally on a uid-less `AppUser`, and the ONE moment
//  a backend identity appears is share-code entry — the act of seeking parental consent.
//
//  Written in the FR-27 house style (`ChildRegistrationOrderingTests`): the sequence is
//  transcribed deterministically against the real policy types, with no Firebase, no
//  timing and no device repro, so the ordering is pinned by test rather than by comment.
//

import Foundation
import Testing
@testable import LicensePlateApp

// MARK: - FR-60(a): the provisioning gate

@MainActor
struct FR60ProvisioningPolicyTests {

    private func makeStore() -> AgeGateStore {
        let suite = "FR60ProvisioningPolicyTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return AgeGateStore(defaults: defaults)
    }

    /// The whole matrix in one place. The under-13 row is the change FR-60 makes; every
    /// other row must be exactly what FR-27 already guaranteed.
    @Test func provisioningMatrix() {
        // Unanswered epoch — FR-27, unchanged: never, not even for redemption. A session
        // with no answer is not a child seeking consent, it is a session that has not been
        // asked yet, and provisioning it would be collection before age resolution.
        #expect(GuestProvisioningPolicy.mayCreateAnonymousIdentity(category: nil) == false)
        #expect(GuestProvisioningPolicy.mayCreateAnonymousIdentity(
            category: nil, isConsentSeekingRedemption: true
        ) == false)

        // 13+ — FR-27, unchanged: provisions on any path.
        #expect(GuestProvisioningPolicy.mayCreateAnonymousIdentity(category: .teenAdult) == true)
        #expect(GuestProvisioningPolicy.mayCreateAnonymousIdentity(
            category: .teenAdult, isConsentSeekingRedemption: true
        ) == true)

        // Under 13 — FR-60(a): no ordinary path provisions any more...
        #expect(GuestProvisioningPolicy.mayCreateAnonymousIdentity(category: .under13) == false)
        // ...and FR-60(b)'s single exception is the consent-seeking act itself.
        #expect(GuestProvisioningPolicy.mayCreateAnonymousIdentity(
            category: .under13, isConsentSeekingRedemption: true
        ) == true)
    }

    /// The default matters: every existing call site (relaunch, first launch, the deferred
    /// post-age-gate provisioning, sign-out and post-deletion rebirth) omits the override,
    /// so omission must mean "not consent-seeking".
    @Test func theConsentSeekingOverrideDefaultsToOff() {
        #expect(GuestProvisioningPolicy.mayCreateAnonymousIdentity(category: .under13) == false)
    }

    /// An under-13 answer still does everything FR-27 requires of it — it just stops
    /// provisioning. The obligation is recorded; nothing is bound, because there is no uid.
    @Test func anUnder13AnswerRecordsTheObligationWithoutProvisioning() {
        let store = makeStore()
        store.recordAnswer(.under13)

        #expect(store.isResolved == true)
        #expect(store.category == .under13)
        #expect(store.hasPendingChildDeclaration == true)
        #expect(GuestProvisioningPolicy.mayCreateAnonymousIdentity(category: store.category) == false)
        // Nothing to hold and nothing to declare: no uid exists to owe one.
        #expect(store.hasOutstandingChildDeclaration == false)
        #expect(store.pendingDeclarationUserIds.isEmpty)
    }

    /// FR-60's acceptance criterion, stated as a client-side invariant: with no uid, there
    /// is no `users/{uid}` writer to hold, because there is no document any writer could
    /// address. The zero-Firestore-doc claim is structural, not a matter of timing.
    @Test func aLocalOnlyChildHasNoDocumentAnyWriterCouldCreate() {
        let store = makeStore()
        store.recordAnswer(.under13)

        #expect(UserDocumentWritePolicy.isWriteHeld(
            userId: nil, pendingDeclarationUserIds: store.pendingDeclarationUserIds
        ) == false)
        #expect(AgeGateProfileWritePolicy.isProfileWriteHeld(
            userUid: nil, pendingDeclarationUserIds: store.pendingDeclarationUserIds
        ) == false)
    }

    /// The posture engine keys off the epoch ANSWER, not off a uid, so a uid-less child is
    /// still `.childDirected` — no ads, no analytics, no location, no purchases. This is
    /// what makes "no backend identity" safe rather than a protection hole.
    @Test func aUidLessUnder13SessionStillGetsTheChildPosture() {
        let posture = ChildSessionPosturePolicy.posture(for: ChildSessionSignal(
            hasCurrentUser: false,
            isAnonymousOrSignedOut: true,
            freshIsChildAccount: nil,
            cachedIsChildAccount: nil,
            // `Dependencies.live().isDeclaredChildIdentity(nil)` returns true for an
            // under-13 epoch precisely so this case is covered before any uid exists.
            isDeclaredChildIdentity: true,
            isAgeResolved: true,
            isDeviceRatcheted: false
        ))

        #expect(posture == .childDirected)
        #expect(posture.isAdDisplayEligible == false)
        #expect(posture.childDirectedTreatment == true)
        #expect(posture.forcesLocationOff == true)
        #expect(posture.suppressesPurchases == true)
    }

    /// A uid-less ADULT guest is unaffected: still `.unresolved`-or-better, never classified
    /// as a child by the FR-60 change.
    @Test func aUidLessAdultGuestIsNotSweptIntoTheChildPosture() {
        let posture = ChildSessionPosturePolicy.posture(for: ChildSessionSignal(
            hasCurrentUser: false,
            isAnonymousOrSignedOut: true,
            freshIsChildAccount: nil,
            cachedIsChildAccount: nil,
            isDeclaredChildIdentity: false,
            isAgeResolved: true,
            isDeviceRatcheted: false
        ))
        #expect(posture == .unresolved)
    }
}

// MARK: - FR-60(b): the redemption sequence

@MainActor
struct FR60RedemptionSequenceTests {

    private func makeStore() -> AgeGateStore {
        let suite = "FR60RedemptionSequenceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return AgeGateStore(defaults: defaults)
    }

    /// The order itself. Stated as data rather than prose so a reordering fails a test
    /// instead of surviving a code review.
    @Test func theSequenceIsMintThenBindThenDeclareThenRedeem() {
        #expect(ChildConsentRedemptionPolicy.orderedSteps == [
            .mintAnonymousIdentity,
            .bindDeclaration,
            .declareChildRegistration,
            .redeemShareCode
        ])
        // FR-27's bind-before-publish discipline, as an ordering fact: binding precedes the
        // declaration, and the declaration precedes redemption.
        #expect(ChildConsentRedemptionPolicy.Step.bindDeclaration
                < ChildConsentRedemptionPolicy.Step.declareChildRegistration)
        #expect(ChildConsentRedemptionPolicy.Step.declareChildRegistration
                < ChildConsentRedemptionPolicy.Step.redeemShareCode)
    }

    @Test func onlyAUidLessUnder13SessionProvisionsAtRedemption() {
        // The FR-60 case.
        #expect(ChildConsentRedemptionPolicy.requiresProvisioning(
            hasFirebaseUid: false, category: .under13
        ) == true)
        // Already provisioned (declined once and re-entering, or sticky post-revocation):
        // straight to redemption, no second identity.
        #expect(ChildConsentRedemptionPolicy.requiresProvisioning(
            hasFirebaseUid: true, category: .under13
        ) == false)
        // Adults and unanswered epochs are not this flow's business.
        #expect(ChildConsentRedemptionPolicy.requiresProvisioning(
            hasFirebaseUid: false, category: .teenAdult
        ) == false)
        #expect(ChildConsentRedemptionPolicy.requiresProvisioning(
            hasFirebaseUid: false, category: nil
        ) == false)
    }

    /// Mid-sequence failure. A declaration that never reached the server leaves the uid
    /// BOUND and the redemption REFUSED — the two halves of the same guarantee. Redeeming
    /// anyway would present an unflagged account to the family, and the captain's approval
    /// would admit a child as an adult.
    @Test func aFailedDeclarationBlocksRedemptionAndLeavesTheUidBoundAndHeld() {
        let store = makeStore()
        store.recordAnswer(.under13)

        // Step 1+2: the uid is minted and bound synchronously, before it can be published.
        let uid = "anon-uid-1"
        let outstanding = store.bindAndCheckDeclarationOutstanding(forFlowUserId: uid)
        #expect(outstanding == true)

        // Step 3 fails (offline blip, App Check, transport). Nothing marks it sent.
        #expect(store.isPendingDeclaration(userId: uid) == true)
        #expect(ChildConsentRedemptionPolicy.mayRedeem(
            hasFirebaseUid: true, isDeclarationOutstanding: true
        ) == false)

        // The uid is never left unbound: its profile write is held by the same machinery
        // FR-27 already uses, so no flagless `users/{uid}` can appear in the meantime.
        #expect(UserDocumentWritePolicy.isWriteHeld(
            userId: uid, pendingDeclarationUserIds: store.pendingDeclarationUserIds
        ) == true)

        // Step 3 succeeds on retry; only then is step 4 permitted.
        store.markChildDeclarationSent(userId: uid)
        #expect(ChildConsentRedemptionPolicy.mayRedeem(
            hasFirebaseUid: true, isDeclarationOutstanding: store.isPendingDeclaration(userId: uid)
        ) == true)
        #expect(UserDocumentWritePolicy.isWriteHeld(
            userId: uid, pendingDeclarationUserIds: store.pendingDeclarationUserIds
        ) == false)
        #expect(store.isDeclaredChildUserId(uid) == true)
    }

    @Test func redemptionIsNeverPermittedWithoutAUid() {
        #expect(ChildConsentRedemptionPolicy.mayRedeem(
            hasFirebaseUid: false, isDeclarationOutstanding: false
        ) == false)
    }

    /// The client-side half of the server carve-out. It opens for a DECLARED CHILD session
    /// only — an ordinary anonymous guest stays blocked, which is what keeps the client gate
    /// strictly narrower than `assertRegisteredAccountOrDeclaredChild`.
    @Test func theConsentExitGateAdmitsADeclaredChildAndNobodyElseAnonymous() {
        #expect(FriendsFamilyAccessPolicy.blocksConsentExitAccess(
            accountState: .firebaseAnonymous, hasFirebaseSession: true, isDeclaredChildSession: true
        ) == false)
        #expect(FriendsFamilyAccessPolicy.blocksConsentExitAccess(
            accountState: .firebaseAnonymous, hasFirebaseSession: true, isDeclaredChildSession: false
        ) == true)
        #expect(FriendsFamilyAccessPolicy.blocksConsentExitAccess(
            accountState: .signedIn, hasFirebaseSession: true, isDeclaredChildSession: false
        ) == false)
        // A live Firebase session is still mandatory — the uid-less child provisions FIRST.
        #expect(FriendsFamilyAccessPolicy.blocksConsentExitAccess(
            accountState: .localGuest, hasFirebaseSession: false, isDeclaredChildSession: true
        ) == true)
    }

    /// Regression guard for the ordinary Friends & Family gate: FR-60 must not loosen it.
    /// Only the two consent exits changed.
    @Test func theOrdinaryFriendsFamilyGateIsUnchanged() {
        #expect(FriendsFamilyAccessPolicy.blocksCallableAccess(
            accountState: .firebaseAnonymous, hasFirebaseSession: true
        ) == true)
        #expect(FriendsFamilyAccessPolicy.blocksCallableAccess(
            accountState: .signedIn, hasFirebaseSession: true
        ) == false)
    }
}

// MARK: - FR-60(d): local history survives the identity transition

@MainActor
struct FR60LocalPlayIdentityRebindTests {

    private let oldId = "3F2E1D00-0000-0000-0000-00000000AAAA"
    private let newUid = "firebase-uid-1"

    @Test func rebindRunsOnlyWhenThereIsSomethingToMove() {
        #expect(LocalPlayIdentityRebindPolicy.shouldRebind(
            previousUserId: oldId, newUserId: newUid
        ) == true)
        #expect(LocalPlayIdentityRebindPolicy.shouldRebind(
            previousUserId: nil, newUserId: newUid
        ) == false)
        #expect(LocalPlayIdentityRebindPolicy.shouldRebind(
            previousUserId: "", newUserId: newUid
        ) == false)
        #expect(LocalPlayIdentityRebindPolicy.shouldRebind(
            previousUserId: oldId, newUserId: oldId
        ) == false)
        // Rebinding onto an empty id would erase ownership rather than move it.
        #expect(LocalPlayIdentityRebindPolicy.shouldRebind(
            previousUserId: oldId, newUserId: ""
        ) == false)
    }

    @Test func onlyExactMatchesAreRewritten() {
        #expect(LocalPlayIdentityRebindPolicy.rebound(oldId, from: oldId, to: newUid) == newUid)
        #expect(LocalPlayIdentityRebindPolicy.rebound("someone-else", from: oldId, to: newUid) == "someone-else")
        #expect(LocalPlayIdentityRebindPolicy.rebound(nil, from: oldId, to: newUid) == nil)
    }

    @Test func theParticipantRosterMovesAndCoParticipantsDoNot() throws {
        let participants = [
            TripParticipant(userId: oldId, role: .owner),
            TripParticipant(userId: "sibling-uid", role: .member)
        ]
        let data = try JSONEncoder().encode(participants)

        let rebound = try #require(LocalPlayIdentityRebindPolicy.reboundParticipantsData(
            data, from: oldId, to: newUid
        ))
        let decoded = try JSONDecoder().decode([TripParticipant].self, from: rebound)

        #expect(decoded.map(\.userId) == [newUid, "sibling-uid"])
        #expect(decoded[0].role == .owner)
    }

    @Test func aRosterWithoutTheOldIdIsLeftUntouched() throws {
        let data = try JSONEncoder().encode([TripParticipant(userId: "sibling-uid", role: .owner)])
        // nil means "nothing changed", so the caller skips the write and the pass stays a
        // genuine no-op on re-run.
        #expect(LocalPlayIdentityRebindPolicy.reboundParticipantsData(
            data, from: oldId, to: newUid
        ) == nil)
        #expect(LocalPlayIdentityRebindPolicy.reboundParticipantsData(
            nil, from: oldId, to: newUid
        ) == nil)
    }

    @Test func everyPayloadValueNamingTheOldIdMoves() throws {
        let payload = [
            TripActivityEventPayloadKey.participantId: oldId,
            TripActivityEventPayloadKey.regionId: "US-CA",
            TripActivityEventPayloadKey.firstFinderParticipantId: oldId,
            TripActivityEventPayloadKey.inputMethod: "voice"
        ]
        let data = try JSONEncoder().encode(payload)

        let rebound = try #require(LocalPlayIdentityRebindPolicy.reboundPayloadData(
            data, from: oldId, to: newUid
        ))
        let decoded = try JSONDecoder().decode([String: String].self, from: rebound)

        #expect(decoded[TripActivityEventPayloadKey.participantId] == newUid)
        #expect(decoded[TripActivityEventPayloadKey.firstFinderParticipantId] == newUid)
        // Non-identity values are never touched — the rewrite is scoped by equality with
        // one device-local UUID, not by key name.
        #expect(decoded[TripActivityEventPayloadKey.regionId] == "US-CA")
        #expect(decoded[TripActivityEventPayloadKey.inputMethod] == "voice")
    }

    @Test func aPayloadWithoutTheOldIdIsLeftUntouched() throws {
        let data = try JSONEncoder().encode([
            TripActivityEventPayloadKey.participantId: "sibling-uid"
        ])
        #expect(LocalPlayIdentityRebindPolicy.reboundPayloadData(data, from: oldId, to: newUid) == nil)
        #expect(LocalPlayIdentityRebindPolicy.reboundPayloadData(nil, from: oldId, to: newUid) == nil)
    }

    /// Idempotence, which is what makes a partially-applied rebind safe to retry: after one
    /// pass nothing equals the old id, so a second pass finds nothing to do.
    @Test func aSecondPassIsANoOp() throws {
        let data = try JSONEncoder().encode([
            TripActivityEventPayloadKey.participantId: oldId
        ])
        let once = try #require(LocalPlayIdentityRebindPolicy.reboundPayloadData(
            data, from: oldId, to: newUid
        ))
        #expect(LocalPlayIdentityRebindPolicy.reboundPayloadData(once, from: oldId, to: newUid) == nil)
    }
}
