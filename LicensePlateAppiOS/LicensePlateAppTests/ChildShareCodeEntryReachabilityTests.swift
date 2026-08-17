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

    /// The sign-up gate is for ADULT guests only. COPPA FR-85 (F-42) inverts the prior
    /// expectation here: this test used to pin `isGuestLike: true` + `.unconsentedChild`
    /// ⇒ `.signUpGate`, which was correct while children registered with credentials.
    /// FR-60 made both child postures guest-like at the auth layer (unconsented = no
    /// Firebase account, consented = anonymous), so a registration-first route now sends
    /// every child to a wall they cannot pass — the unconsented child loses share-code
    /// entry, the only path to consent, and the consented child loses the family surface
    /// they were already admitted to.
    @Test func theSignUpGateIsForAdultGuestsOnly() {
        let adultGuest = FriendsFamilyGateRouting.destination(
            isGuestLike: true,
            childState: .notChild,
            feature: .family
        )
        #expect(adultGuest == .signUpGate)
        #expect(!adultGuest.offersShareCodeEntry)
    }

    @Test func aGuestLikeChildSessionStillReachesItsChildSurface() {
        // Unconsented: keeps the gate that owns "Join a Family".
        let unconsented = FriendsFamilyGateRouting.destination(
            isGuestLike: true,
            childState: .unconsentedChild,
            feature: .family
        )
        #expect(unconsented == .childGate(.unconsented))
        #expect(unconsented.offersShareCodeEntry)

        // Consented: an anonymous account (FR-60) still gets the real family surface.
        #expect(
            FriendsFamilyGateRouting.destination(
                isGuestLike: true, childState: .consentedChild, feature: .family
            ) == .content
        )

        // ...and friends stay closed for them regardless of auth shape (FR-14/24).
        #expect(
            FriendsFamilyGateRouting.destination(
                isGuestLike: true, childState: .consentedChild, feature: .friends
            ) == .childGate(.consented)
        )
    }

    // MARK: - Entry point 1b: what the family screen SAYS while a request is outstanding

    /// Device pass 2026-08-17 (fix 2). Wave 3b taught the home banner and the profile card to
    /// say "your request is waiting"; the FAMILY TAB was left behind, and it is the surface a
    /// child actually opens to check. An unconsented child with a live pending request saw
    /// the same "join a family with a share code" screen as a child who had sent nothing.
    @Test func theFamilyGateSaysAnApprovalIsWaitingWhenOneIs() {
        let waiting = ChildAccountGateView.presentation(
            state: .unconsented,
            isFamilyApprovalPending: true
        )
        #expect(waiting.titleKey == "child_gate.family_prompt.pending_title")
        #expect(waiting.bodyKey == "auth_status.child.pending_guidance_body")
        #expect(waiting.iconOverride == "hourglass")

        // The copy actually differs from the generic prompt — otherwise the fix is a no-op.
        let generic = ChildAccountGateView.presentation(
            state: .unconsented,
            isFamilyApprovalPending: false
        )
        #expect(generic.titleKey == "child_gate.screen.join_title")
        #expect(generic.bodyKey == "child_gate.screen.join_body")
        #expect(waiting != generic)
    }

    /// FR-28f: the child must never be stranded. If the request is stale, or went to the
    /// wrong family, share-code entry is still on the screen — the waiting copy replaces the
    /// prompt, it does not remove the route.
    @Test func theWaitingVariantKeepsShareCodeEntryReachable() {
        for pending in [true, false] {
            let presentation = ChildAccountGateView.presentation(
                state: .unconsented,
                isFamilyApprovalPending: pending
            )
            #expect(
                presentation.showsJoinFamilyButton,
                "pending=\(pending) removed the child's only route into a family"
            )
        }
    }

    /// A consented child has a family, so there is nothing to wait for. The flag is cleared
    /// the moment membership arrives; ignoring it here means one that somehow outlived its
    /// own clear cannot stack "waiting" on top of a session that is already in.
    @Test func theConsentedVariantIgnoresAStalePendingFlag() {
        let consented = ChildAccountGateView.presentation(
            state: .consented,
            isFamilyApprovalPending: true
        )
        #expect(consented == ChildAccountGateView.presentation(
            state: .consented,
            isFamilyApprovalPending: false
        ))
        #expect(consented.titleKey == "child_gate.screen.friends_title")
        #expect(consented.showsJoinFamilyButton == false)
    }

    /// The gate's waiting copy is driven by the SAME device-local flag as the home banner, so
    /// the two surfaces cannot disagree about whether a request is outstanding.
    @Test func theGateAndTheBannerAgreeAboutWaiting() {
        let service = makeService(under13: true, declaredUid: "child-1", familyId: nil)
        #expect(service.isFamilyApprovalPending == false)
        #expect(
            ChildAccountGateView.presentation(
                state: .unconsented,
                isFamilyApprovalPending: service.isFamilyApprovalPending
            ).titleKey == "child_gate.screen.join_title"
        )

        service.markFamilyApprovalPending()
        #expect(service.isFamilyApprovalPending == true)
        // The banner's waiting title, on the family screen, from one flag.
        #expect(
            ChildAccountGateView.presentation(
                state: .unconsented,
                isFamilyApprovalPending: service.isFamilyApprovalPending
            ).titleKey == "child_gate.family_prompt.pending_title"
        )
        #expect(service.familyPromptPresentation == .full)

        // ...and it clears together, too.
        service.clearFamilyApprovalPending()
        #expect(
            ChildAccountGateView.presentation(
                state: .unconsented,
                isFamilyApprovalPending: service.isFamilyApprovalPending
            ).titleKey == "child_gate.screen.join_title"
        )
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
