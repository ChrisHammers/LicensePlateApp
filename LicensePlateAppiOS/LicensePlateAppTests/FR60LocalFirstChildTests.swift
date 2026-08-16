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

// MARK: - FR-60(a) on a RESTORED identity (owner device pass 2026-08-15, bug 3)

/// "Deleted the app, reinstalled. The Keychain restored the old anonymous uid, Firestore had
/// been wiped. Answered 2013/2014/2022 and got: a generic 'User' name, NO child banner,
/// anonymous 'Sign up to access' gates, location correctly disabled, and a `users/{uid}` doc
/// written to the cloud — the same doc all three times, because the same uid came back."
///
/// FR-60(a) stops an under-13 answer CREATING an identity. It never considered one that
/// already existed, and the two halves of the system then disagreed about the same session:
/// the flow-scoped half read the ANSWER (location off — correct), the identity-bound half read
/// whether the uid was BOUND to it (banner, gates, write holds — all wrong). The result is the
/// exact population FR-60 exists to keep off the server acquiring a flagless `users/{uid}`.
@MainActor
struct FR60RestoredIdentityTests {

    private let restoredUid = "restored-keychain-anon-uid"

    private func makeStore(suite: String = "FR60RestoredIdentityTests") -> (AgeGateStore, UserDefaults) {
        let name = "\(suite)-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (AgeGateStore(defaults: defaults), defaults)
    }

    @Test func theDetachMatrix() {
        // The reported case: under-13 answered onto a restored anonymous session it does not own.
        #expect(RestoredIdentityAgeAnswerPolicy.requiresLocalDetach(
            category: .under13, isAnonymousSession: true, isBoundToCurrentAnswer: false
        ) == true)

        // The ordinary FR-60(b) case — a uid THIS answer provisioned — must never detach, or
        // share-code redemption would tear down the identity it just minted.
        #expect(RestoredIdentityAgeAnswerPolicy.requiresLocalDetach(
            category: .under13, isAnonymousSession: true, isBoundToCurrentAnswer: true
        ) == false)

        // A registered session is out of scope: it has credentials, its owner can sign back
        // in, and FR-27 forbids an age answer touching a pre-existing account at all.
        #expect(RestoredIdentityAgeAnswerPolicy.requiresLocalDetach(
            category: .under13, isAnonymousSession: false, isBoundToCurrentAnswer: false
        ) == false)

        // FR-74(d′) asymmetry: only the PROTECTIVE answer displaces a restored identity.
        #expect(RestoredIdentityAgeAnswerPolicy.requiresLocalDetach(
            category: .teenAdult, isAnonymousSession: true, isBoundToCurrentAnswer: false
        ) == false)
        #expect(RestoredIdentityAgeAnswerPolicy.requiresLocalDetach(
            category: nil, isAnonymousSession: true, isBoundToCurrentAnswer: false
        ) == false)
    }

    /// The chimera itself, reproduced against the real classifier and then resolved. The banner
    /// is not cosmetic — it is the unconsented child's ONLY route to share-code entry, so
    /// losing it strands them.
    @Test func theRestoredIdentityLosesTheChildBannerUntilItIsDetached() {
        let (store, defaults) = makeStore()
        let service = ChildRestrictedModeService(ageGateStore: store, defaults: defaults)
        store.recordAnswer(.under13)

        // THE BUG: the uid is present but unbound, so the identity-bound branch classifies the
        // session `.notChild` — no FR-28 banner, adult gates.
        var currentUid: String? = restoredUid
        service.configure(
            currentUserIdProvider: { currentUid },
            activeFamilyIdProvider: { nil }
        )
        #expect(service.childSessionState == .notChild)
        #expect(service.isRestrictedUnconsentedChild == false)
        #expect(service.familyPromptPresentation == .hidden)

        // THE FIX: detaching returns the session to the uid-less local-first child FR-60
        // specifies, which the pre-uid provisional branch classifies correctly.
        currentUid = nil
        #expect(service.childSessionState == .unconsentedChild)
        #expect(service.isRestrictedUnconsentedChild == true)
        #expect(service.familyPromptPresentation == .full)
    }

    /// The cloud-footprint half. An unbound uid is held by nothing, so every `users/{uid}`
    /// writer is free to create a FLAGLESS document for a child — which reads back as an adult
    /// because Firestore rules forbid `isChildAccount` on create.
    @Test func anUnboundRestoredUidIsHeldByNothingUntilItIsDetached() {
        let (store, _) = makeStore()
        store.recordAnswer(.under13)

        // THE BUG: nothing holds it.
        #expect(store.isPendingDeclaration(userId: restoredUid) == false)
        #expect(UserDocumentWritePolicy.isWriteHeld(
            userId: restoredUid,
            pendingDeclarationUserIds: store.pendingDeclarationUserIds,
            detachedIdentityUserIds: store.detachedIdentityUserIds
        ) == false)

        // THE FIX: after the detach the uid is retired for good, and the session has no uid a
        // writer could address at all (FR-60's zero-footprint claim, restored).
        store.markIdentityDetached(userId: restoredUid)
        #expect(UserDocumentWritePolicy.isWriteHeld(
            userId: restoredUid,
            pendingDeclarationUserIds: store.pendingDeclarationUserIds,
            detachedIdentityUserIds: store.detachedIdentityUserIds
        ) == true)
        #expect(UserDocumentWritePolicy.isWriteHeld(
            userId: nil,
            pendingDeclarationUserIds: store.pendingDeclarationUserIds,
            detachedIdentityUserIds: store.detachedIdentityUserIds
        ) == false)
    }

    /// FR-60(a) is not weakened by any of this: the detached session still cannot provision.
    /// Only the consent-seeking act can, and only once the child asks for it.
    @Test func aDetachedChildSessionStillMayNotProvision() {
        let (store, _) = makeStore()
        store.recordAnswer(.under13)
        store.markIdentityDetached(userId: restoredUid)

        #expect(GuestProvisioningPolicy.mayCreateAnonymousIdentity(category: store.category) == false)
        #expect(GuestProvisioningPolicy.mayCreateAnonymousIdentity(
            category: store.category, isConsentSeekingRedemption: true
        ) == true)
        #expect(ChildConsentRedemptionPolicy.requiresProvisioning(
            hasFirebaseUid: false, category: store.category
        ) == true)
    }
}

// MARK: - FR-60(b) promotion keeps the player's chosen profile (owner device pass 2026-08-15)

/// "The child's avatar and username are LOST at redemption-time provisioning — the cloud
/// profile carries defaults instead."
///
/// The profile write was never the problem: `firestoreDataFromAppUser` serialises `userName`
/// and `avatarId` off whatever `AppUser` it is handed. What changed underneath it is WHICH
/// `AppUser` that is. Minting the uid fires the auth-state listener, whose bootstrap sees a
/// brand-new uid with no local row and no cloud doc, and does the only sane thing for a
/// genuinely new account: it builds a fresh `AppUser` with a device-default username and no
/// avatar, publishes it as `currentUser`, and saves THAT.
///
/// Before FR-60 that was harmless — the local `AppUser` was a placeholder for milliseconds.
/// The local-first child picks an avatar in onboarding and plays for days before any uid
/// exists, so the same race now publishes a stranger to the family they are asking to join.
/// The fix is ownership (`uidsBeingProvisionedLocally` keeps the bootstrap out of a flow's
/// uid); this policy is the second line, deciding when a promotion must carry the profile.
@MainActor
struct FR60LocalPlayerPromotionTests {

    /// The FR-60 case: an anonymous uid minted for a player who had none.
    @Test func promotingThisDevicesUnprovisionedPlayerCarriesTheirProfile() {
        #expect(LocalPlayerPromotionPolicy.carriesLocalProfile(
            isAnonymousSession: true, localPlayerHasFirebaseUid: false
        ) == true)
    }

    /// A registered sign-in must never inherit a guest's identity off the same device — the
    /// avatar and name on the local row belong to whoever was playing, not to the account
    /// being signed into.
    @Test func aRegisteredSignInNeverInheritsTheLocalPlayersProfile() {
        #expect(LocalPlayerPromotionPolicy.carriesLocalProfile(
            isAnonymousSession: false, localPlayerHasFirebaseUid: false
        ) == false)
    }

    /// A local player who already holds a uid is not being promoted; some other account is
    /// being loaded, and carrying this one's profile onto it would be a cross-identity leak.
    @Test func anAlreadyProvisionedPlayerIsNotAPromotion() {
        #expect(LocalPlayerPromotionPolicy.carriesLocalProfile(
            isAnonymousSession: true, localPlayerHasFirebaseUid: true
        ) == false)
        #expect(LocalPlayerPromotionPolicy.carriesLocalProfile(
            isAnonymousSession: false, localPlayerHasFirebaseUid: true
        ) == false)
    }

    /// The promotion is also an identity change, so it owes FR-60(d) the same rebind the
    /// redemption path performs — the carried profile and the carried play history have to
    /// name the same uid or the child arrives with an avatar and no trips.
    @Test func aPromotionAlsoOwesTheLocalPlayHistoryRebind() {
        let localId = "3F2E1D00-0000-0000-0000-00000000AAAA"
        #expect(LocalPlayIdentityRebindPolicy.shouldRebind(
            previousUserId: localId, newUserId: "minted-anon-uid"
        ) == true)
    }
}

// MARK: - FR-60(c) zombie uid (owner device pass 2026-08-15, bug 4)

/// "After the captain declined — and separately after Remove-and-delete — the child device
/// showed 'Create an account to use friends and family features' on every new share-code
/// attempt; and the DELETED child's uid got RESURRECTED server-side: an AppPrefs doc plus
/// lastLoggedIn/lastUpdated fields appeared on reopen."
///
/// FR-60(c) deletes the Auth user and `users/{uid}` and deliberately preserves the device's
/// age answer and ratchet, on the premise that the child "re-enters a fresh code later and
/// re-provisions cleanly". The device also keeps the UID — in the Keychain, on
/// `AppUser.firebaseUID`, and in `declaredChildUserIds` — and both
/// `ChildConsentRedemptionPolicy.requiresProvisioning` and `signInAnonymously` short-circuit
/// on a non-nil uid, so the re-provision never happens. Same root, both symptoms.
@MainActor
struct FR60DetachedIdentityTests {

    private let deletedUid = "declined-child-uid"

    private func makeStore() -> AgeGateStore {
        let suite = "FR60DetachedIdentityTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return AgeGateStore(defaults: defaults)
    }

    /// An existing uid may no longer be trusted on sight; the redemption sequence has to check
    /// it before it decides to skip provisioning.
    @Test func anExistingChildUidIsVerifiedBeforeTheSkip() {
        #expect(ChildConsentRedemptionPolicy.requiresIdentityVerification(
            hasFirebaseUid: true, category: .under13
        ) == true)
        // Nothing to verify when there is no uid — that is the ordinary provisioning case.
        #expect(ChildConsentRedemptionPolicy.requiresIdentityVerification(
            hasFirebaseUid: false, category: .under13
        ) == false)
        // Adults and unanswered epochs are not this flow's business (unchanged from FR-60(b)).
        #expect(ChildConsentRedemptionPolicy.requiresIdentityVerification(
            hasFirebaseUid: true, category: .teenAdult
        ) == false)
        #expect(ChildConsentRedemptionPolicy.requiresIdentityVerification(
            hasFirebaseUid: true, category: nil
        ) == false)
    }

    @Test func theDetachMatrix() {
        typealias Status = DetachedIdentityDetectionPolicy.SelfDocumentStatus

        // The reported case: a uid this device declared, whose document is confirmed gone.
        #expect(DetachedIdentityDetectionPolicy.requiresDetach(
            isAnonymousSession: true, documentStatus: .confirmedAbsent, wasDeclaredByThisDevice: true
        ) == true)

        // A live account is left alone.
        #expect(DetachedIdentityDetectionPolicy.requiresDetach(
            isAnonymousSession: true, documentStatus: .present, wasDeclaredByThisDevice: true
        ) == false)

        // An UNREADABLE server is never absence. An offline relaunch must not cost a live
        // account its session — and an anonymous session, once dropped, is unrecoverable.
        #expect(DetachedIdentityDetectionPolicy.requiresDetach(
            isAnonymousSession: true, documentStatus: .unknown, wasDeclaredByThisDevice: true
        ) == false)

        // A uid whose declaration has NOT been delivered yet is out of scope: its document is
        // supposed to be absent (the write is held), so absence proves nothing. Without this
        // the rule would sign a child out seconds after minting their uid.
        #expect(DetachedIdentityDetectionPolicy.requiresDetach(
            isAnonymousSession: true, documentStatus: .confirmedAbsent, wasDeclaredByThisDevice: false
        ) == false)

        // Registered accounts are never detached — they have credentials and a sign-in route.
        #expect(DetachedIdentityDetectionPolicy.requiresDetach(
            isAnonymousSession: false, documentStatus: .confirmedAbsent, wasDeclaredByThisDevice: true
        ) == false)
    }

    /// Why the existing hold never covered this — the answer to "the `UserDocumentWritePolicy`
    /// hold should cover it; find why it didn't".
    ///
    /// The pending-declaration hold is a hold on an OBLIGATION, and it releases the moment the
    /// obligation is met. A deleted child's declaration had been met long ago, so from the
    /// hold's point of view the uid was in perfect standing — and `updateLoginTimestamps` and
    /// the `appPrefs` writers, all `setData(merge: true)`, recreated the document.
    @Test func thePendingDeclarationHoldReleasesWhichIsWhyItNeverCoveredADeletedChild() {
        let store = makeStore()
        store.recordAnswer(.under13)
        store.bindPendingDeclaration(toUserId: deletedUid)

        // Held while the declaration is outstanding...
        #expect(UserDocumentWritePolicy.isWriteHeld(
            userId: deletedUid,
            pendingDeclarationUserIds: store.pendingDeclarationUserIds,
            detachedIdentityUserIds: store.detachedIdentityUserIds
        ) == true)

        // ...and released the instant it lands. THIS is the hole: everything after this point
        // — including the server deleting the account — leaves the uid freely writable.
        store.markChildDeclarationSent(userId: deletedUid)
        #expect(store.isDeclaredChildUserId(deletedUid) == true)
        #expect(UserDocumentWritePolicy.isWriteHeld(
            userId: deletedUid,
            pendingDeclarationUserIds: store.pendingDeclarationUserIds,
            detachedIdentityUserIds: store.detachedIdentityUserIds
        ) == false)

        // The detached set is the closure: a one-way ratchet with no release condition.
        store.markIdentityDetached(userId: deletedUid)
        #expect(UserDocumentWritePolicy.isWriteHeld(
            userId: deletedUid,
            pendingDeclarationUserIds: store.pendingDeclarationUserIds,
            detachedIdentityUserIds: store.detachedIdentityUserIds
        ) == true)
        #expect(AgeGateProfileWritePolicy.isProfileWriteHeld(
            userUid: deletedUid,
            pendingDeclarationUserIds: store.pendingDeclarationUserIds,
            detachedIdentityUserIds: store.detachedIdentityUserIds
        ) == true)
    }

    /// The hold outlives the epoch. A sign-out clears the answer, and the resurrection writers
    /// do not care about the answer at all — so a release here would reopen the hole.
    @Test func theDetachedHoldSurvivesSignOutAndOtherIdentities() {
        let store = makeStore()
        store.recordAnswer(.under13)
        store.markIdentityDetached(userId: deletedUid)

        store.clearAnswer()
        #expect(store.isResolved == false)
        #expect(store.detachedIdentityUserIds.contains(deletedUid))
        #expect(UserDocumentWritePolicy.isWriteHeld(
            userId: deletedUid,
            pendingDeclarationUserIds: store.pendingDeclarationUserIds,
            detachedIdentityUserIds: store.detachedIdentityUserIds
        ) == true)

        // Scoped to the retired uid only — a different account on the same device is untouched.
        #expect(UserDocumentWritePolicy.isWriteHeld(
            userId: "some-other-account",
            pendingDeclarationUserIds: store.pendingDeclarationUserIds,
            detachedIdentityUserIds: store.detachedIdentityUserIds
        ) == false)
    }

    /// After the detach the child is back where FR-60(c)'s cleanup intended them to be: a
    /// uid-less local-first child who re-provisions on the next share code. The device ratchet
    /// the cleanup deliberately preserved is preserved here too.
    @Test func aDetachedChildReProvisionsOnTheNextShareCodeWithTheRatchetIntact() {
        let store = makeStore()
        store.recordAnswer(.under13)
        store.bindPendingDeclaration(toUserId: deletedUid)
        store.markChildDeclarationSent(userId: deletedUid)

        // THE BUG: the uid is present, so the sequence skips provisioning and redeems with a
        // dead identity — refused by the server as unregistered, on every code, forever.
        #expect(ChildConsentRedemptionPolicy.requiresProvisioning(
            hasFirebaseUid: true, category: store.category
        ) == false)

        store.markIdentityDetached(userId: deletedUid)

        // THE FIX: a uid-less child provisions again, and the whole FR-60(b) sequence re-runs
        // for the NEW uid — bind, declare, then redeem.
        #expect(ChildConsentRedemptionPolicy.requiresProvisioning(
            hasFirebaseUid: false, category: store.category
        ) == true)

        let freshUid = "reprovisioned-child-uid"
        #expect(store.bindAndCheckDeclarationOutstanding(forFlowUserId: freshUid) == true)
        #expect(ChildConsentRedemptionPolicy.mayRedeem(
            hasFirebaseUid: true, isDeclarationOutstanding: true
        ) == false)
        store.markChildDeclarationSent(userId: freshUid)
        #expect(ChildConsentRedemptionPolicy.mayRedeem(
            hasFirebaseUid: true, isDeclarationOutstanding: store.isPendingDeclaration(userId: freshUid)
        ) == true)

        // Device ratchet intact: the answer, the declared history and the retired uid all
        // survive, so nothing about the protective posture is softened by the recovery.
        #expect(store.category == .under13)
        #expect(store.hasDeclaredChildHistory == true)
        #expect(store.isDeclaredChildUserId(deletedUid) == true)
        #expect(store.detachedIdentityUserIds.contains(deletedUid))
        // ...and the retired uid stays unwritable even while the fresh one is live.
        #expect(UserDocumentWritePolicy.isWriteHeld(
            userId: deletedUid,
            pendingDeclarationUserIds: store.pendingDeclarationUserIds,
            detachedIdentityUserIds: store.detachedIdentityUserIds
        ) == true)
        #expect(UserDocumentWritePolicy.isWriteHeld(
            userId: freshUid,
            pendingDeclarationUserIds: store.pendingDeclarationUserIds,
            detachedIdentityUserIds: store.detachedIdentityUserIds
        ) == false)
    }

    // MARK: - Eager detection (device pass 2026-08-16, bug 1)

    /// Wave 1 answered "what did we see?" and left "when do we look?" to whichever identity
    /// edge happened to fire. A captain's remove-and-delete fires none of them on the child's
    /// device — the app is in the FOREGROUND, the account disappears server-side, and the
    /// cached ID token keeps authenticating for the rest of its hour.
    @Test func theVerificationMatrixSaysWhenToLook() {
        // The reported case: an anonymous, declared child holding a uid, online, not yet
        // retired. Worth a round-trip on every foreground.
        #expect(DetachedIdentityDetectionPolicy.requiresVerification(
            hasFirebaseUid: true, isAnonymousSession: true, wasDeclaredByThisDevice: true,
            isAlreadyDetached: false, isOnline: true
        ) == true)

        // FR-60's local-first child has no identity to verify.
        #expect(DetachedIdentityDetectionPolicy.requiresVerification(
            hasFirebaseUid: false, isAnonymousSession: true, wasDeclaredByThisDevice: true,
            isAlreadyDetached: false, isOnline: true
        ) == false)

        // Registered accounts are out of scope — they have credentials and a sign-in route,
        // and are never detached (same scope as `requiresDetach`).
        #expect(DetachedIdentityDetectionPolicy.requiresVerification(
            hasFirebaseUid: true, isAnonymousSession: false, wasDeclaredByThisDevice: true,
            isAlreadyDetached: false, isOnline: true
        ) == false)

        // An adult guest's anonymous uid: nothing was declared, so absence proves nothing and
        // a foreground check would be a read per foreground for no verdict.
        #expect(DetachedIdentityDetectionPolicy.requiresVerification(
            hasFirebaseUid: true, isAnonymousSession: true, wasDeclaredByThisDevice: false,
            isAlreadyDetached: false, isOnline: true
        ) == false)

        // One-way ratchet: a uid already retired is never re-examined.
        #expect(DetachedIdentityDetectionPolicy.requiresVerification(
            hasFirebaseUid: true, isAnonymousSession: true, wasDeclaredByThisDevice: true,
            isAlreadyDetached: true, isOnline: true
        ) == false)

        // Offline is not absence; the round-trip could only return `.unknown`.
        #expect(DetachedIdentityDetectionPolicy.requiresVerification(
            hasFirebaseUid: true, isAnonymousSession: true, wasDeclaredByThisDevice: true,
            isAlreadyDetached: false, isOnline: false
        ) == false)
    }

    /// The self-sealing window, transcribed. This is the mechanism behind the owner's report:
    /// the deletion is only detectable while `users/{uid}` is absent, and the FIRST self-doc
    /// write inside the window puts a document back. After that every later check reads
    /// `.present` and the zombie is permanent.
    @Test func aResurrectionWriteInsideTheWindowHidesTheDeletionFromEveryLaterCheck() {
        typealias Status = DetachedIdentityDetectionPolicy.SelfDocumentStatus
        let store = makeStore()
        store.recordAnswer(.under13)
        store.bindPendingDeclaration(toUserId: deletedUid)
        store.markChildDeclarationSent(userId: deletedUid)

        // Captain deletes. The document is gone, so the verdict is available...
        #expect(DetachedIdentityDetectionPolicy.requiresDetach(
            isAnonymousSession: true, documentStatus: .confirmedAbsent,
            wasDeclaredByThisDevice: store.isDeclaredChildUserId(deletedUid)
        ) == true)

        // ...but nothing had LOOKED yet, so the uid was still writable and an avatar edit
        // recreated the document. From here `requiresDetach` can never fire again.
        let statusAfterResurrection: Status = .present
        #expect(DetachedIdentityDetectionPolicy.requiresDetach(
            isAnonymousSession: true, documentStatus: statusAfterResurrection,
            wasDeclaredByThisDevice: store.isDeclaredChildUserId(deletedUid)
        ) == false)

        // Two independent closures, both required. (1) Look on foreground and session
        // restore, so the window is entered by a READ before a write can reach it.
        #expect(DetachedIdentityDetectionPolicy.requiresVerification(
            hasFirebaseUid: true, isAnonymousSession: true,
            wasDeclaredByThisDevice: store.isDeclaredChildUserId(deletedUid),
            isAlreadyDetached: false, isOnline: true
        ) == true)

        // (2) Once retired, the uid is never re-adopted even if a document exists for it
        // again — otherwise the resurrection could un-ratchet the ratchet.
        store.markIdentityDetached(userId: deletedUid)
        #expect(store.isIdentityDetached(deletedUid) == true)
        #expect(store.isIdentityDetached("some-other-uid") == false)
        #expect(store.isIdentityDetached(nil) == false)
    }

    /// Every self-doc writer on the client is held for a retired uid — including the one the
    /// avatar edit uses, whose only precondition used to be "a `firebaseUID` exists".
    ///
    /// `saveUserDataToFirestore` resolves its target as `firebaseUID ?? id`, and a detach nils
    /// `firebaseUID` while deliberately leaving the retired uid on `id` (so `firebaseUID ?? id`
    /// still resolves the player's local trips and XP). Both spellings must be held.
    @Test func aRetiredUidIsHeldFromEitherIdentityField() {
        let store = makeStore()
        store.recordAnswer(.under13)
        store.markIdentityDetached(userId: deletedUid)

        // The post-detach shape: `firebaseUID == nil`, `id == deletedUid`.
        #expect(store.isIdentityDetached(nil) == false)          // firebaseUID
        #expect(store.isIdentityDetached(deletedUid) == true)    // id — the resolved target
        #expect(AgeGateProfileWritePolicy.isProfileWriteHeld(
            userUid: deletedUid,
            pendingDeclarationUserIds: store.pendingDeclarationUserIds,
            detachedIdentityUserIds: store.detachedIdentityUserIds
        ) == true)

        // A re-provisioned player carries a fresh uid on BOTH fields and is not held.
        let freshUid = "reprovisioned-child-uid"
        #expect(store.isIdentityDetached(freshUid) == false)
        #expect(AgeGateProfileWritePolicy.isProfileWriteHeld(
            userUid: freshUid,
            pendingDeclarationUserIds: store.pendingDeclarationUserIds,
            detachedIdentityUserIds: store.detachedIdentityUserIds
        ) == false)
    }

    // MARK: - The hybrid (device pass 2026-08-16, bug 1)

    /// The owner's screenshot, as a classification problem.
    ///
    /// The Authentication Status card resolved its HEADER from `isAnonymousUser ||
    /// firebaseUID != nil` and its BODY from `childSessionState`. Those are two different
    /// questions, so a child holding a uid answered them differently: an adult's "Anonymous
    /// Account — sign up to sync…" headline stacked on a child's "join a family" body.
    ///
    /// One classification cannot disagree with itself, which is why the policy decides both.
    @Test func aChildHoldingAUidIsNeverLabelledAnAnonymousAdult() {
        let hybridInputs = AuthenticationStatusPolicy.Inputs(
            isAnonymousSession: true,
            hasFirebaseUid: true,
            childSessionState: .unconsentedChild,
            wasEverInFamily: true
        )
        let state = AuthenticationStatusPolicy.state(for: hybridInputs)
        #expect(state == .postRevocationChild)

        let presentation = AuthenticationStatusPolicy.presentation(for: state)
        #expect(presentation.headerKey != "Anonymous Account")
        #expect(presentation.showsSignIn == false)
        #expect(presentation.showsJoinFamily == true)
    }

    /// The settle, stated as an invariant: after a detach the session is a plain local-first
    /// child, indistinguishable from one that never had an identity. Anything that survives
    /// the detach — a uid on the profile row, a lingering `activeFamilyId`, a pending-approval
    /// flag — reintroduces a second answer to "what is this session?", which is the hybrid.
    @Test func theDetachedChildIsIndistinguishableFromAFreshLocalChild() {
        let freshLocalChild = AuthenticationStatusPolicy.Inputs(
            childSessionState: .unconsentedChild
        )
        let detachedChild = AuthenticationStatusPolicy.Inputs(
            childSessionState: .unconsentedChild,
            isIdentityDetached: true,
            // Was in a family before the captain deleted the account — and it must not matter,
            // because the identity that membership belonged to no longer exists.
            wasEverInFamily: true
        )

        #expect(AuthenticationStatusPolicy.state(for: freshLocalChild) == .localUnconsentedChild)
        #expect(AuthenticationStatusPolicy.state(for: detachedChild) == .localUnconsentedChild)
        #expect(
            AuthenticationStatusPolicy.presentation(for: freshLocalChild)
                == AuthenticationStatusPolicy.presentation(for: detachedChild)
        )
    }
}
