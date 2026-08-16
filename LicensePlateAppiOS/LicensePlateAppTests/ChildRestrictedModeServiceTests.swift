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
        activeFamilyId: String?,
        cachedIsChild: [String: Bool] = [:],
        resolvedIsChild: [String: Bool] = [:]
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
        let cache = ChildSignalCache(defaults: defaults)
        for (uid, value) in cachedIsChild {
            cache.setCachedIsChildAccount(value, for: uid)
        }
        let service = ChildRestrictedModeService(
            ageGateStore: store,
            defaults: defaults,
            childSignalCache: cache
        )
        service.configure(
            currentUserIdProvider: { currentUserId },
            activeFamilyIdProvider: { activeFamilyId },
            resolvedIsChildAccountProvider: { resolvedIsChild[$0] }
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
        #expect(GuestProvisioningPolicy.mayCreateAnonymousIdentity(category: store.category) == false)

        let rebornGuest = ChildRestrictedModeService(ageGateStore: store, defaults: defaults)
        rebornGuest.configure(
            currentUserIdProvider: { nil }, // unprovisioned — no uid exists
            activeFamilyIdProvider: { nil }
        )
        #expect(rebornGuest.childSessionState == .notChild) // standard guest gate, not child banner
        #expect(rebornGuest.isRestrictedUnconsentedChild == false)
        #expect(rebornGuest.isAgeUnresolved == true) // F-7 fail-closed surface
        #expect(AgeGateProfileWritePolicy.isProfileWriteHeld(
            userUid: "any-uid", pendingDeclarationUserIds: store.pendingDeclarationUserIds
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
        let childSession = ChildRestrictedModeService(ageGateStore: store, defaults: defaults)
        childSession.configure(
            currentUserIdProvider: { "uid-new-child-guest" },
            activeFamilyIdProvider: { nil }
        )
        #expect(childSession.childSessionState == .unconsentedChild)
        #expect(childSession.isGameplayCloudSyncPaused == true)

        // Parent's account: untouched — not restricted, profile writes never held,
        // and never a declaration target (only the flow-bound uid ever was).
        let parentSession = ChildRestrictedModeService(ageGateStore: store, defaults: defaults)
        parentSession.configure(
            currentUserIdProvider: { "uid-parent" },
            activeFamilyIdProvider: { "family-parent" }
        )
        #expect(parentSession.childSessionState == .notChild)
        #expect(store.isDeclaredChildUserId("uid-parent") == false)
        #expect(AgeGateProfileWritePolicy.isProfileWriteHeld(
            userUid: "uid-parent",
            pendingDeclarationUserIds: store.pendingDeclarationUserIds
        ) == false)
    }

    // MARK: - Server-resolved child truth (owner repro 2026-08-12)

    /// Owner device repro: manager corrects the child (device age-gate markers wiped by
    /// the F-8 correction path), re-flags them, then removes them from the family. The
    /// device lineage is gone, so the server flag — mirrored in the cache — is the only
    /// remaining signal, and it MUST classify the session as a restricted child.
    @Test func regrantAfterCorrection_cachedTrueAloneRestoresRestriction() {
        let service = makeService(
            category: nil, // under-13 answer wiped by the correction
            currentUserId: "uid-child",
            activeFamilyId: nil, // removed from family
            cachedIsChild: ["uid-child": true]
        )
        #expect(service.childSessionState == .unconsentedChild)
        #expect(service.isRestrictedUnconsentedChild == true)
        #expect(service.isGameplayCloudSyncPaused == true)
    }

    /// Same repro via the fresh projection only (cache not yet written): classification
    /// must not depend on notification-observer ordering between the posture
    /// coordinator's cache write and the UI's refresh.
    @Test func regrantAfterCorrection_freshProjectionAloneRestoresRestriction() {
        let service = makeService(
            category: nil,
            currentUserId: "uid-child",
            activeFamilyId: nil,
            resolvedIsChild: ["uid-child": true]
        )
        #expect(service.childSessionState == .unconsentedChild)
        #expect(service.isGameplayCloudSyncPaused == true)
    }

    /// A child account signing in on a device that never ran the age gate for it
    /// (fresh install, second device): server truth classifies; family splits state.
    @Test func freshDeviceChildSignIn_classifiesFromServerTruth() {
        let inFamily = makeService(
            category: nil,
            currentUserId: "uid-child",
            activeFamilyId: "family-1",
            cachedIsChild: ["uid-child": true]
        )
        #expect(inFamily.childSessionState == .consentedChild)

        let familyless = makeService(
            category: nil,
            currentUserId: "uid-child",
            activeFamilyId: nil,
            cachedIsChild: ["uid-child": true]
        )
        #expect(familyless.childSessionState == .unconsentedChild)
    }

    /// Identity binding holds for the server-resolved source too (incident-1 property):
    /// another uid's cached-true never restricts the signed-in account.
    @Test func cachedTrueIsIdentityBound() {
        let service = makeService(
            category: nil,
            currentUserId: "uid-adult",
            activeFamilyId: nil,
            cachedIsChild: ["uid-child": true]
        )
        #expect(service.childSessionState == .notChild)
        #expect(service.isGameplayCloudSyncPaused == false)
    }

    /// FR-19 asymmetry in this consumer too: false/absent server values never restrict
    /// (and never resurrect a corrected account's restriction).
    @Test func cachedOrResolvedFalseNeverRestricts() {
        let service = makeService(
            category: nil,
            currentUserId: "uid-1",
            activeFamilyId: nil,
            cachedIsChild: ["uid-1": false],
            resolvedIsChild: ["uid-1": false]
        )
        #expect(service.childSessionState == .notChild)
    }

    /// Full lifecycle walk on one store/cache pair: declared child → manager correction
    /// (device markers wiped, cache entry cleared → adult) → manager re-grant (server
    /// true re-cached → restricted child again once familyless). Pins that the
    /// correction still fully lifts AND that the re-grant fully restores.
    @Test func correctionThenRegrantLifecycle() {
        let suite = "ChildRestrictedModeServiceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = AgeGateStore(defaults: defaults)
        let cache = ChildSignalCache(defaults: defaults)
        var activeFamilyId: String? = "family-1"

        // Declared child, admitted to a family (consented).
        store.recordAnswer(.under13)
        store.bindPendingDeclaration(toUserId: "uid-child")
        store.markChildDeclarationSent(userId: "uid-child")
        cache.setCachedIsChildAccount(true, for: "uid-child")

        let service = ChildRestrictedModeService(
            ageGateStore: store, defaults: defaults, childSignalCache: cache
        )
        service.configure(
            currentUserIdProvider: { "uid-child" },
            activeFamilyIdProvider: { activeFamilyId }
        )
        #expect(service.childSessionState == .consentedChild)

        // Manager CORRECTION — mirrors ChildSessionPostureCoordinator's live path:
        // lineage cleared for the uid, then device markers lifted.
        store.clearDeclaredChildUserId("uid-child")
        cache.clearCachedIsChildAccount(for: "uid-child")
        cache.disengageDeviceRatchet()
        store.clearUnder13AnswerAfterCorrection()
        #expect(service.childSessionState == .notChild)

        // Manager RE-GRANT — server flag true arrives; the posture seam re-caches it.
        cache.setCachedIsChildAccount(true, for: "uid-child")
        #expect(service.childSessionState == .consentedChild)

        // Removal (REVOKED, flag sticky): restricted child, not an adult.
        activeFamilyId = nil
        #expect(service.childSessionState == .unconsentedChild)
        #expect(service.isGameplayCloudSyncPaused == true)
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

    // MARK: - Pending family approval (F-8 device testing, 2026-08-15)

    @Test func markingPendingApprovalIsVisibleToTheSameIdentity() {
        let service = makeService(
            category: .under13,
            declarationSentForUserId: "uid-child",
            currentUserId: "uid-child",
            activeFamilyId: nil
        )
        #expect(service.isFamilyApprovalPending == false)
        service.markFamilyApprovalPending()
        #expect(service.isFamilyApprovalPending == true)
    }

    @Test func clearingPendingApprovalLiftsTheFlag() {
        let service = makeService(
            category: .under13,
            declarationSentForUserId: "uid-child",
            currentUserId: "uid-child",
            activeFamilyId: nil
        )
        service.markFamilyApprovalPending()
        #expect(service.isFamilyApprovalPending == true)
        service.clearFamilyApprovalPending()
        #expect(service.isFamilyApprovalPending == false)
        // Idempotent: clearing an already-clear flag is a safe no-op.
        service.clearFamilyApprovalPending()
        #expect(service.isFamilyApprovalPending == false)
    }

    @Test func markingPendingApprovalWithNoCurrentUserIsANoOp() {
        let service = makeService(
            category: .under13,
            currentUserId: nil,
            activeFamilyId: nil
        )
        service.markFamilyApprovalPending()
        #expect(service.isFamilyApprovalPending == false)
    }

    /// Incident-1 pattern applied to the new flag: the stored uid is the whole safety
    /// argument, so a later different identity sharing this device's UserDefaults must
    /// never read a previous identity's pending redemption as its own.
    @Test func pendingApprovalIsIdentityBound() {
        let suite = "ChildRestrictedModeServiceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = AgeGateStore(defaults: defaults)
        store.recordAnswer(.under13)
        store.bindPendingDeclaration(toUserId: "uid-child")
        store.markChildDeclarationSent(userId: "uid-child")

        let childService = ChildRestrictedModeService(ageGateStore: store, defaults: defaults)
        childService.configure(
            currentUserIdProvider: { "uid-child" },
            activeFamilyIdProvider: { nil }
        )
        childService.markFamilyApprovalPending()
        #expect(childService.isFamilyApprovalPending == true)

        // Same device, same UserDefaults suite, a DIFFERENT current identity (e.g. a
        // sign-out/rebirth, or a parent's own account) — must read as not pending.
        let otherService = ChildRestrictedModeService(ageGateStore: store, defaults: defaults)
        otherService.configure(
            currentUserIdProvider: { "uid-other" },
            activeFamilyIdProvider: { nil }
        )
        #expect(otherService.isFamilyApprovalPending == false)

        // No current identity at all (signed out) also reads as not pending.
        let signedOutService = ChildRestrictedModeService(ageGateStore: store, defaults: defaults)
        signedOutService.configure(
            currentUserIdProvider: { nil },
            activeFamilyIdProvider: { nil }
        )
        #expect(signedOutService.isFamilyApprovalPending == false)
    }

    /// Full lifecycle: redemption marks it, and the clear this device's ContentView
    /// issues once membership arrives (or the restriction otherwise lifts) removes it —
    /// the exact two edges the fix requires, driven through the same service a third
    /// identity never sees.
    @Test func pendingApprovalLifecycle_redeemThenApprovalClears() {
        let service = makeService(
            category: .under13,
            declarationSentForUserId: "uid-child",
            currentUserId: "uid-child",
            activeFamilyId: nil
        )
        #expect(service.childSessionState == .unconsentedChild)

        // Redemption succeeds (`FamilyRepository.redeemShareCode`'s call).
        service.markFamilyApprovalPending()
        #expect(service.isFamilyApprovalPending == true)

        // Captain approves — membership arrives, lifting the restriction. ContentView's
        // `refreshChildFamilyPrompt()` clears the flag once `isRestrictedUnconsentedChild`
        // is false; simulated here as the same explicit call.
        service.clearFamilyApprovalPending()
        #expect(service.isFamilyApprovalPending == false)
    }

    // MARK: - Pending approval stays visible (device pass 2026-08-16, bug 3)

    /// The owner's report: "once the join sheet is dismissed the state is never shown again —
    /// I had multiple children pending and couldn't tell which was which."
    ///
    /// Two separate causes. This is the first: the prompt collapses to a COMPACT row after its
    /// one full-size introduction, and the compact row shows the title only — so the waiting
    /// state, whose whole message is in the subtitle, was reduced to a one-line chevron. The
    /// waiting variant now always renders full-size.
    @Test func theWaitingPromptIsAlwaysFullSizeEvenAfterTheIntroductionIsSpent() {
        // Ordinary restricted child, introduction already spent ⇒ compact, as before.
        #expect(ChildFamilyPromptPolicy.presentation(
            isRestrictedUnconsentedChild: true,
            hasPresentedFullBanner: true,
            isFamilyApprovalPending: false
        ) == .compact)

        // Same child, now waiting on a captain ⇒ full, subtitle and all.
        #expect(ChildFamilyPromptPolicy.presentation(
            isRestrictedUnconsentedChild: true,
            hasPresentedFullBanner: true,
            isFamilyApprovalPending: true
        ) == .full)
    }

    /// The flag is identity-bound and only a child session can set it, so if it is up the
    /// child is owed the status — regardless of how the FR-28 classification happens to be
    /// resolving at that instant (a posture read in flight, a cache miss, a family edge
    /// mid-delivery). Otherwise the one state the child most needs to see is also the one
    /// most likely to be swallowed by a transient reclassification.
    @Test func aPendingRequestIsShownEvenIfTheRestrictionClassificationSaysHidden() {
        #expect(ChildFamilyPromptPolicy.presentation(
            isRestrictedUnconsentedChild: false,
            hasPresentedFullBanner: true,
            isFamilyApprovalPending: true
        ) == .full)

        // And with nothing pending, an unrestricted session still shows nothing.
        #expect(ChildFamilyPromptPolicy.presentation(
            isRestrictedUnconsentedChild: false,
            hasPresentedFullBanner: true,
            isFamilyApprovalPending: false
        ) == .hidden)
    }

    /// End to end through the real service: redeeming marks it, the presentation goes to the
    /// waiting variant and STAYS there across arbitrarily many re-reads (a dismissed sheet, a
    /// relaunch, a scene-phase change), until membership arrives.
    @Test func theWaitingPromptSurvivesEveryRereadUntilMembershipArrives() {
        var activeFamilyId: String?
        let suite = "ChildRestrictedModeServiceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = AgeGateStore(defaults: defaults)
        store.recordAnswer(.under13)
        store.bindPendingDeclaration(toUserId: "uid-child")
        store.markChildDeclarationSent(userId: "uid-child")

        let service = ChildRestrictedModeService(ageGateStore: store, defaults: defaults)
        service.configure(
            currentUserIdProvider: { "uid-child" },
            activeFamilyIdProvider: { activeFamilyId }
        )

        // Introduction shown and spent — the pre-redemption steady state.
        #expect(service.familyPromptPresentation == .full)
        service.markFullFamilyPromptPresented()
        #expect(service.familyPromptPresentation == .compact)

        // Share code submitted.
        service.markFamilyApprovalPending()
        for _ in 0..<5 {
            #expect(service.familyPromptPresentation == .full)
            #expect(service.isFamilyApprovalPending == true)
        }

        // Captain approves: membership arrives, the restriction lifts, and the host clears the
        // flag (ContentView's `refreshChildFamilyPrompt`, transcribed).
        activeFamilyId = "family-1"
        #expect(service.isRestrictedUnconsentedChild == false)
        service.clearFamilyApprovalPending()
        #expect(service.familyPromptPresentation == .hidden)
    }

    /// The second cause: the flag had no publisher, so a redemption started from anywhere
    /// other than the banner's own sheet (the profile card, onboarding, the child gate) set it
    /// with nobody listening. A published `revision` is what makes the flag observable; these
    /// are the mutations that must move it.
    @Test func everyPendingApprovalMutationPublishesARevision() {
        let service = makeService(
            category: .under13,
            declarationSentForUserId: "uid-child",
            currentUserId: "uid-child",
            activeFamilyId: nil
        )
        let start = service.revision

        service.markFamilyApprovalPending()
        #expect(service.revision > start)

        // Idempotent: re-marking the SAME identity is not a change and must not churn every
        // observer (this is read from view-update handlers).
        let afterMark = service.revision
        service.markFamilyApprovalPending()
        #expect(service.revision == afterMark)

        service.clearFamilyApprovalPending()
        #expect(service.revision > afterMark)

        let afterClear = service.revision
        service.clearFamilyApprovalPending()
        #expect(service.revision == afterClear)

        service.markFullFamilyPromptPresented()
        #expect(service.revision > afterClear)

        // ...and that one is a one-shot too, so the observer loop it feeds terminates.
        let afterPresented = service.revision
        service.markFullFamilyPromptPresented()
        #expect(service.revision == afterPresented)
    }

    /// A detach (decline, remove-and-delete) resets the identity, and the waiting state must
    /// go with it — a child cannot be waiting on a captain who is looking at nothing. The flag
    /// is uid-bound, so a detached, uid-less session already reads false; the explicit clear in
    /// `detachAnonymousIdentityLocally` also frees the stored key.
    @Test func aDetachedIdentityIsNotWaitingOnAnybody() {
        var currentUid: String? = "uid-child"
        let suite = "ChildRestrictedModeServiceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = AgeGateStore(defaults: defaults)
        store.recordAnswer(.under13)
        store.bindPendingDeclaration(toUserId: "uid-child")
        store.markChildDeclarationSent(userId: "uid-child")

        let service = ChildRestrictedModeService(ageGateStore: store, defaults: defaults)
        service.configure(
            currentUserIdProvider: { currentUid },
            activeFamilyIdProvider: { nil }
        )
        service.markFamilyApprovalPending()
        #expect(service.isFamilyApprovalPending == true)

        // The detach: uid retired, session back to uid-less local-first child.
        store.markIdentityDetached(userId: "uid-child")
        currentUid = nil
        service.clearFamilyApprovalPending()

        #expect(service.isFamilyApprovalPending == false)
        // ...and the child is back on the ordinary "ask a parent" prompt, not a stale wait.
        #expect(service.childSessionState == .unconsentedChild)
        #expect(service.familyPromptPresentation != .hidden)
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
