//
//  ChildRestrictedModeServiceTests.swift
//  LicensePlateAppTests
//
//  COPPA F-6 (FR-28 client half, flow-scoped rework): child session classification,
//  sync-hold gating, onboarding routing decision, and unconsented-child rejection
//  classification — including the incident-1 captain regression.
//

import Foundation
import FirebaseFunctions
import Testing
@testable import LicensePlateApp

@MainActor
struct ChildRestrictedModeServiceTests {

    private func makeService(
        category: AgeGateCategory?,
        boundPendingUserId: String? = nil,
        declarationSentForUserId: String? = nil,
        currentUserId: String?,
        activeFamilyId: String?
    ) -> ChildRestrictedModeService {
        let suite = "ChildRestrictedModeServiceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = AgeGateStore(defaults: defaults)
        if let category {
            store.recordAnswer(category)
        }
        if let boundPendingUserId {
            store.bindPendingDeclaration(toUserId: boundPendingUserId)
        }
        if let declarationSentForUserId {
            store.markChildDeclarationSent(userId: declarationSentForUserId)
        }
        let service = ChildRestrictedModeService(ageGateStore: store)
        service.configure(
            currentUserIdProvider: { currentUserId },
            activeFamilyIdProvider: { activeFamilyId }
        )
        return service
    }

    // MARK: - Restriction matrix

    @Test func declaredChildWithoutFamilyIsRestricted() {
        let service = makeService(
            category: .under13,
            declarationSentForUserId: "uid-1",
            currentUserId: "uid-1",
            activeFamilyId: nil
        )
        #expect(service.childSessionState == .unconsentedChild)
        #expect(service.isRestrictedUnconsentedChild == true)
        #expect(service.isGameplayCloudSyncPaused == true)
    }

    @Test func flowBoundUidAwaitingDeclarationIsRestricted() {
        let service = makeService(
            category: .under13,
            boundPendingUserId: "uid-1",
            currentUserId: "uid-1",
            activeFamilyId: nil
        )
        #expect(service.childSessionState == .unconsentedChild)
        #expect(service.isGameplayCloudSyncPaused == true)
    }

    @Test func preUidProvisionalGuestIsRestricted() {
        let service = makeService(
            category: .under13,
            currentUserId: nil,
            activeFamilyId: nil
        )
        #expect(service.childSessionState == .unconsentedChild)
    }

    @Test func familyAdmissionLiftsRestrictionButStaysChild() {
        let service = makeService(
            category: .under13,
            declarationSentForUserId: "uid-1",
            currentUserId: "uid-1",
            activeFamilyId: "family-1"
        )
        #expect(service.childSessionState == .consentedChild)
        #expect(service.isRestrictedUnconsentedChild == false)
        #expect(service.isGameplayCloudSyncPaused == false)
    }

    @Test func teenAdultIsNeverChild() {
        let service = makeService(
            category: .teenAdult,
            currentUserId: "uid-1",
            activeFamilyId: nil
        )
        #expect(service.childSessionState == .notChild)
        #expect(service.isRestrictedUnconsentedChild == false)
    }

    @Test func unresolvedAgeIsNotChild() {
        let service = makeService(
            category: nil,
            currentUserId: "uid-1",
            activeFamilyId: nil
        )
        #expect(service.childSessionState == .notChild)
    }

    /// Incident-1 regression (owner device, 2026-08-11): an existing signed-in captain
    /// with a stale, unbound under-13 answer on the device is NOT a child session —
    /// no restriction, no sync hold. Identity binding is required.
    @Test func incident1Regression_staleAnswerDoesNotRestrictExistingSignedInAccount() {
        let service = makeService(
            category: .under13, // stale unbound answer (pending, never bound to a uid)
            currentUserId: "captain-uid",
            activeFamilyId: nil
        )
        #expect(service.childSessionState == .notChild)
        #expect(service.isRestrictedUnconsentedChild == false)
        #expect(service.isGameplayCloudSyncPaused == false)
    }

    @Test func anotherUsersDeclarationDoesNotRestrictADifferentAccount() {
        let service = makeService(
            category: .under13,
            declarationSentForUserId: "uid-child",
            currentUserId: "uid-adult",
            activeFamilyId: nil
        )
        #expect(service.childSessionState == .notChild)
    }

    /// Option-B rebirth regression (owner decision): sign-out rebirth produces a
    /// RESTRICTED guest, not a prompt. The new guest never provisions (no anonymous
    /// uid, no users/{uid} write), is age-unresolved for F-7's fail-closed postures,
    /// and shows the STANDARD guest gates — not the child banner (age-unknown is not a
    /// declared child). A later sign-up asks fresh and, on under-13, declares the uid
    /// that sign-up creates.
    @Test func signOutRebirth_producesRestrictedGuestNotPrompt() {
        let suite = "ChildRestrictedModeServiceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = AgeGateStore(defaults: defaults)

        // Previous epoch ends at sign-out.
        store.recordAnswer(.teenAdult)
        store.clearAnswer()

        // Reborn guest: no provisioning, no prompt state, no child classification.
        #expect(GuestProvisioningPolicy.mayCreateAnonymousIdentity(isResolved: store.isResolved) == false)

        let rebornGuest = ChildRestrictedModeService(ageGateStore: store)
        rebornGuest.configure(
            currentUserIdProvider: { nil }, // unprovisioned — no uid exists
            activeFamilyIdProvider: { nil }
        )
        #expect(rebornGuest.childSessionState == .notChild) // standard guest gate, not child banner
        #expect(rebornGuest.isRestrictedUnconsentedChild == false)
        #expect(rebornGuest.isAgeUnresolved == true) // F-7 fail-closed surface
        #expect(AgeGateProfileWritePolicy.isProfileWriteHeld(
            userUid: "any-uid", pendingDeclarationUserId: store.pendingDeclarationUserId
        ) == false)

        // Sign-up asks fresh (epoch unanswered ⇒ SignInView create mode shows the
        // age screen) and an under-13 answer declares the uid sign-up creates.
        #expect(store.isResolved == false)
        store.recordAnswer(.under13)
        store.bindPendingDeclaration(toUserId: "uid-signup-child")
        store.markChildDeclarationSent(userId: "uid-signup-child")
        #expect(store.isDeclaredChildUserId("uid-signup-child") == true)
        #expect(rebornGuest.isAgeUnresolved == false)
    }

    /// Shared-device narrative (owner-review regression, option B): parent signs out →
    /// child picks up the phone → plays locally as the restricted guest (no prompt) →
    /// taps Create Account → the sign-up flow asks the age question → under-13 answer
    /// binds + declares the NEW uid — while the parent's account is untouched (not
    /// held, not restricted, never a declaration target).
    @Test func sharedDeviceNarrative_signOutThenChildAnswer_declaresOnlyTheNewGuest() {
        let suite = "ChildRestrictedModeServiceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = AgeGateStore(defaults: defaults)

        // Parent epoch ends at sign-out (nothing stored survives but uid history).
        store.clearAnswer()

        // Child answers at SIGN-UP; the flow binds + declares the NEW uid it creates.
        store.recordAnswer(.under13)
        store.bindPendingDeclaration(toUserId: "uid-new-child-guest")
        store.markChildDeclarationSent(userId: "uid-new-child-guest")

        // New guest session: child, restricted, sync paused.
        let childSession = ChildRestrictedModeService(ageGateStore: store)
        childSession.configure(
            currentUserIdProvider: { "uid-new-child-guest" },
            activeFamilyIdProvider: { nil }
        )
        #expect(childSession.childSessionState == .unconsentedChild)
        #expect(childSession.isGameplayCloudSyncPaused == true)

        // Parent's account: untouched — not restricted, profile writes never held,
        // and never a declaration target (only the flow-bound uid ever was).
        let parentSession = ChildRestrictedModeService(ageGateStore: store)
        parentSession.configure(
            currentUserIdProvider: { "uid-parent" },
            activeFamilyIdProvider: { "family-parent" }
        )
        #expect(parentSession.childSessionState == .notChild)
        #expect(store.isDeclaredChildUserId("uid-parent") == false)
        #expect(AgeGateProfileWritePolicy.isProfileWriteHeld(
            userUid: "uid-parent",
            pendingDeclarationUserId: store.pendingDeclarationUserId
        ) == false)
    }

    // MARK: - Rejection classification (FR-28 friendly-copy mapping)

    @Test func classifiesUnconsentedChildRejection() {
        for reason in ["unconsented_child", "child_account"] {
            let error = NSError(
                domain: FunctionsErrorDomain,
                code: FunctionsErrorCode.failedPrecondition.rawValue,
                userInfo: [FunctionsErrorDetailsKey: ["reason": reason]]
            )
            #expect(ChildRestrictedModeService.isChildRestrictionRejection(error) == true)
        }
    }

    @Test func ignoresOtherFailedPreconditions() {
        let noDetails = NSError(
            domain: FunctionsErrorDomain,
            code: FunctionsErrorCode.failedPrecondition.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "game not found"]
        )
        #expect(ChildRestrictedModeService.isChildRestrictionRejection(noDetails) == false)

        let otherReason = NSError(
            domain: FunctionsErrorDomain,
            code: FunctionsErrorCode.failedPrecondition.rawValue,
            userInfo: [FunctionsErrorDetailsKey: ["reason": "something_else"]]
        )
        #expect(ChildRestrictedModeService.isChildRestrictionRejection(otherReason) == false)

        let wrongCode = NSError(
            domain: FunctionsErrorDomain,
            code: FunctionsErrorCode.permissionDenied.rawValue,
            userInfo: [FunctionsErrorDetailsKey: ["reason": "unconsented_child"]]
        )
        #expect(ChildRestrictedModeService.isChildRestrictionRejection(wrongCode) == false)
    }

    // MARK: - Onboarding routing (FR-27)

    /// Owner placement: the age step sits after the welcome/disclaimer intro and
    /// immediately before account creation, asked only when this identity epoch has
    /// no answer yet.
    @Test func disclaimerRoutesToAgeStepWhenEpochUnanswered() {
        #expect(OnboardingCoordinator.stepAfterDisclaimer(isAgeGateResolved: false) == .ageVerification)
        #expect(OnboardingCoordinator.stepAfterDisclaimer(isAgeGateResolved: true) == .accountCreation)
    }

    @Test func childRoutesJoinFamilyOnly() {
        #expect(OnboardingCoordinator.familySetupStep(ageCategory: .under13) == .joinFamily)
        #expect(OnboardingCoordinator.familySetupStep(ageCategory: .teenAdult) == .createFamily)
        #expect(OnboardingCoordinator.familySetupStep(ageCategory: nil) == .createFamily)
    }
}
