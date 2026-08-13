//
//  ChildShareCodeEntryReachabilityTests.swift
//  LicensePlateAppTests
//
//  Regression: share-code entry is the child's designated path INTO a family (FR-24
//  keeps `redeemShareCode` open to child callers server-side, and the FR-28 banner
//  deep-links to it). A delta that hid it locked unconsented children out entirely.
//
//  These pin the two entry points and the client gate on the redeem call itself.
//

import Foundation
import Testing
@testable import LicensePlateApp

@MainActor
struct ChildShareCodeEntryReachabilityTests {

    private func makeService(
        under13: Bool,
        declaredUid: String?,
        familyId: String?
    ) -> ChildRestrictedModeService {
        let suite = "ChildShareCodeEntryTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let ageStore = AgeGateStore(defaults: defaults)
        if under13 {
            ageStore.recordAnswer(.under13)
            if let declaredUid {
                ageStore.bindPendingDeclaration(toUserId: declaredUid)
                ageStore.markChildDeclarationSent(userId: declaredUid)
            }
        }
        let service = ChildRestrictedModeService(ageGateStore: ageStore, defaults: defaults)
        service.configure(
            currentUserIdProvider: { declaredUid },
            activeFamilyIdProvider: { familyId }
        )
        return service
    }

    // MARK: - Entry point 1: the family screen

    /// The unconsented child must land on the gate variant that OWNS the "Join a Family"
    /// button. `.consented` and the sign-up gate have no share-code entry.
    @Test func anUnconsentedChildLandsOnTheGateThatOffersShareCodeEntry() {
        let service = makeService(under13: true, declaredUid: "child-1", familyId: nil)
        #expect(service.childSessionState == .unconsentedChild)

        let destination = FriendsFamilyGateRouting.destination(
            isGuestLike: false,
            childState: service.childSessionState,
            feature: .family
        )
        #expect(destination == .childGate(.unconsented))
        #expect(destination.offersShareCodeEntry)
    }

    @Test func theSameHoldsForTheFriendsSurface() {
        // Both features route an unconsented child through the join-a-family gate.
        let destination = FriendsFamilyGateRouting.destination(
            isGuestLike: false,
            childState: .unconsentedChild,
            feature: .friends
        )
        #expect(destination == .childGate(.unconsented))
        #expect(destination.offersShareCodeEntry)
    }

    @Test func aConsentedChildKeepsTheFamilySurfaceAndAnAdultIsUngated() {
        #expect(
            FriendsFamilyGateRouting.destination(
                isGuestLike: false, childState: .consentedChild, feature: .family
            ) == .content
        )
        #expect(
            FriendsFamilyGateRouting.destination(
                isGuestLike: false, childState: .notChild, feature: .family
            ) == .content
        )
        // Friends stay closed for a consented child (FR-14/24) — and that variant
        // deliberately has no share-code entry, because they are already in a family.
        let friendsGate = FriendsFamilyGateRouting.destination(
            isGuestLike: false, childState: .consentedChild, feature: .friends
        )
        #expect(friendsGate == .childGate(.consented))
        #expect(!friendsGate.offersShareCodeEntry)
    }

    @Test func onlyTheGuestSignUpGateWithholdsShareCodeEntry() {
        let destination = FriendsFamilyGateRouting.destination(
            isGuestLike: true,
            childState: .unconsentedChild,
            feature: .family
        )
        #expect(destination == .signUpGate)
        #expect(!destination.offersShareCodeEntry)
    }

    // MARK: - Entry point 2: the restricted-state banner

    /// The banner is visible in both presentations for a restricted child, and both are
    /// tappable — it owns the join sheet itself, so nothing upstream can shadow it.
    @Test func theBannerStaysAvailableInBothPresentations() {
        let service = makeService(under13: true, declaredUid: "child-1", familyId: nil)
        #expect(service.familyPromptPresentation == .full)
        #expect(service.familyPromptPresentation.isVisible)

        service.markFullFamilyPromptPresented()
        #expect(service.familyPromptPresentation == .compact)
        #expect(service.familyPromptPresentation.isVisible)
    }

    @Test func theBannerDisappearsOnlyOnceTheChildIsInAFamily() {
        let consented = makeService(under13: true, declaredUid: "child-1", familyId: "fam-1")
        #expect(consented.childSessionState == .consentedChild)
        #expect(consented.familyPromptPresentation == .hidden)
    }

    // MARK: - The redeem call itself

    /// `FamilyRepository.redeemShareCode` gates only on `validateFriendsFamilyCallableAccess`
    /// — a registered account with a live session. Child status is NOT part of that gate
    /// (FR-24), so the call goes out for a child exactly as it does for an adult.
    @Test func theRedeemGateDoesNotBlockARegisteredChild() {
        #expect(
            FriendsFamilyAccessPolicy.blocksCallableAccess(
                accountState: .signedIn,
                hasFirebaseSession: true
            ) == false
        )
    }

    @Test func theRedeemGateStillBlocksGuestsAndSignedOutSessions() {
        #expect(
            FriendsFamilyAccessPolicy.blocksCallableAccess(
                accountState: .firebaseAnonymous,
                hasFirebaseSession: true
            )
        )
        #expect(
            FriendsFamilyAccessPolicy.blocksCallableAccess(
                accountState: .signedIn,
                hasFirebaseSession: false
            )
        )
    }
}
