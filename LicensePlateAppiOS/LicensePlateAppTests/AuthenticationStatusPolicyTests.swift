//
//  AuthenticationStatusPolicyTests.swift
//  LicensePlateAppTests
//
//  Device pass 2026-08-16 (bug 2): UserProfileView's "Authentication Status" card, as a
//  closed state matrix rather than a chain of `if` conditions inside a view body.
//
//  The defect this suite exists for was a DISAGREEMENT, not a wrong string: the header
//  resolved off `isAnonymousUser || firebaseUID != nil` while the section beneath it
//  resolved off `ChildRestrictedModeService.childSessionState`. Two classifications of one
//  session will eventually disagree, and for a consented child they did — an adult's
//  "Anonymous Account. Sign up to sync…" headline over a child's "join a family" body.
//
//  So the tests are about the PARTITION first (every session lands in exactly one state,
//  and child sessions are decided before any uid-shaped state) and the copy second.
//

import Foundation
import Testing
@testable import LicensePlateApp

@MainActor
struct AuthenticationStatusPolicyTests {

    private typealias Inputs = AuthenticationStatusPolicy.Inputs
    private typealias State = AuthenticationStatusState

    private func state(_ inputs: Inputs) -> State {
        AuthenticationStatusPolicy.state(for: inputs)
    }

    private func presentation(_ state: State) -> AuthenticationStatusPresentation {
        AuthenticationStatusPolicy.presentation(for: state)
    }

    // MARK: - (1)–(3) Adult states: byte-identical to the pre-matrix card

    /// (1) Registered adult. The ONLY state with Sign Out and Delete Account — the latter is
    /// Guideline 5.1.1(v)'s requirement, and it belongs to exactly the session that has an
    /// account to delete.
    @Test func registeredAdult() {
        let s = state(Inputs(isRegisteredSession: true, hasFirebaseUid: true))
        #expect(s == .registeredAdult)

        let p = presentation(s)
        #expect(p.headerKey == "Signed In")
        #expect(p.subtitleKey == "Your account is synced to the cloud")
        #expect(p.isCloudSynced == true)
        #expect(p.showsSignIn == false)
        #expect(p.showsDeleteAccount == true)
        #expect(p.showsJoinFamily == false)
        #expect(p.childGuidance == nil)
        #expect(p.childNoticeKey == nil)
    }

    /// The pre-existing signed-out branch. Not in the owner's list of eight but it is a real
    /// state the card already rendered, and "keep adult states byte-identical" covers it.
    @Test func signedOutRegisteredAdult() {
        let s = state(Inputs(wasPreviouslySignedIn: true, hasFirebaseUid: true))
        #expect(s == .signedOutRegisteredAdult)

        let p = presentation(s)
        #expect(p.headerKey == "Signed Out")
        #expect(p.subtitleKey == "You are signed out. Sign in to sync your account and access all features")
        #expect(p.showsSignIn == true)
        #expect(p.showsDeleteAccount == false)
    }

    /// (2) Anonymous adult: 13+ answered, provisioned.
    @Test func anonymousAdult() {
        let s = state(Inputs(
            isAnonymousSession: true,
            hasFirebaseUid: true,
            isAgeAnswerResolved: true
        ))
        #expect(s == .anonymousAdult)

        let p = presentation(s)
        #expect(p.headerKey == "Anonymous Account")
        #expect(p.subtitleKey == "Sign up to sync your account and access more features")
        #expect(p.isCloudSynced == false)
        #expect(p.showsSignIn == true)
        #expect(p.showsDeleteAccount == false)
    }

    /// (3) Restored anonymous uid with no answer for this identity epoch — the reinstall case
    /// that exists until F-30 lands. Deliberately presented as (2): nothing about the session
    /// is known well enough to say anything else, and inventing a third headline would be copy
    /// localized three ways and then deleted.
    @Test func unresolvedRestoredSessionIsPresentedAsAnonymousUntilF30() {
        let s = state(Inputs(
            isAnonymousSession: true,
            hasFirebaseUid: true,
            isAgeAnswerResolved: false
        ))
        #expect(s == .unresolvedRestoredSession)
        #expect(presentation(s) == presentation(.anonymousAdult))
    }

    /// Plain local guest — no uid, no answer, no child signal (offline first launch,
    /// post-sign-out rebirth). The pre-existing "Local Account" copy, unchanged.
    @Test func localAdultGuest() {
        let s = state(Inputs(isAgeAnswerResolved: false))
        #expect(s == .localAdultGuest)

        let p = presentation(s)
        #expect(p.headerKey == "Local Account")
        #expect(p.subtitleKey == "Your account is stored locally only. Sign in to sync to the cloud")
        #expect(p.showsSignIn == true)
    }

    // MARK: - (4)–(7) Child states

    /// (4) FR-60 local-first child. The owner's fix: the header stays "Local Account" (it is
    /// accurate and already localized) and the SUBTITLE stops telling a child to sign in —
    /// the one thing FR-60(e) says they cannot do. The route out is join-a-family, which is
    /// what consent actually is.
    @Test func localUnconsentedChildNeverMentionsSigningIn() {
        let s = state(Inputs(childSessionState: .unconsentedChild))
        #expect(s == .localUnconsentedChild)

        let p = presentation(s)
        #expect(p.headerKey == "Local Account")
        #expect(p.subtitleKey == "auth_status.child.local_subtitle")
        #expect(p.showsSignIn == false)
        #expect(p.showsDeleteAccount == false)
        #expect(p.showsJoinFamily == true)
        #expect(p.childGuidance?.titleKey == "child_gate.screen.join_title")
    }

    /// (5) Share code submitted, captain has not decided. The header and caption are the same
    /// copy the home banner's waiting variant uses, so a child chasing "did it go through?"
    /// gets one answer wherever they look.
    @Test func transientDeclaredChildShowsTheWaitingState() {
        let s = state(Inputs(
            isAnonymousSession: true,
            hasFirebaseUid: true,
            childSessionState: .unconsentedChild,
            isFamilyApprovalPending: true
        ))
        #expect(s == .transientDeclaredChild)

        let p = presentation(s)
        #expect(p.headerKey == "child_gate.family_prompt.pending_title")
        #expect(p.subtitleKey == "child_gate.family_prompt.pending_subtitle")
        #expect(p.showsSignIn == false)
        #expect(p.showsDeleteAccount == false)
        // Still a way out if they sent the code to the wrong family.
        #expect(p.showsJoinFamily == true)
    }

    /// Device pass 2026-08-17 (fix 1). The owner's rule, verbatim: "waiting for approval"
    /// must mean a pending request actually exists; approved, declined, or none-sent all get
    /// the ordinary local-child wording.
    ///
    /// This test previously asserted the OPPOSITE — a uid-holding child with nothing pending
    /// read as `.transientDeclaredChild`, on the theory that "waiting" was the honest
    /// description of a redemption whose outcome the device had lost. On device it was the
    /// opposite of honest: a reinstall restores the uid from the Keychain and wipes the
    /// UserDefaults flag, and remove-and-delete leaves the same shape, so the state was the
    /// FALLBACK for "we know nothing" and told children a family was still deciding about a
    /// request that no longer existed.
    @Test func aUidHoldingChildWithNothingPendingIsAnOrdinaryLocalChild() {
        let s = state(Inputs(
            isAnonymousSession: true,
            hasFirebaseUid: true,
            childSessionState: .unconsentedChild,
            isFamilyApprovalPending: false,
            wasEverInFamily: false
        ))
        #expect(s == .localUnconsentedChild)
        #expect(s != .transientDeclaredChild)

        // The reinstall shape specifically: Keychain kept the uid, UserDefaults did not keep
        // the flag. Identical outcome — nothing about it says a request is outstanding.
        let afterReinstall = state(Inputs(
            isAnonymousSession: true,
            hasFirebaseUid: true,
            childSessionState: .unconsentedChild,
            isFamilyApprovalPending: false,
            isAgeAnswerResolved: false,
            wasEverInFamily: false
        ))
        #expect(afterReinstall == .localUnconsentedChild)
    }

    /// The same child, with the flag up. This is the ONLY input that produces the waiting
    /// copy, which is the point of the rule.
    @Test func onlyALivePendingRequestProducesTheWaitingState() {
        let pending = state(Inputs(
            isAnonymousSession: true,
            hasFirebaseUid: true,
            childSessionState: .unconsentedChild,
            isFamilyApprovalPending: true
        ))
        #expect(pending == .transientDeclaredChild)

        // Exhaustive converse: across every other input axis, no combination without the
        // pending flag reaches the waiting state.
        for isAnonymous in [true, false] {
            for hasUid in [true, false] {
                for everInFamily in [true, false] {
                    for resolved in [true, false] {
                        for detached in [true, false] {
                            let s = state(Inputs(
                                isAnonymousSession: isAnonymous,
                                hasFirebaseUid: hasUid,
                                childSessionState: .unconsentedChild,
                                isFamilyApprovalPending: false,
                                isAgeAnswerResolved: resolved,
                                isIdentityDetached: detached,
                                wasEverInFamily: everInFamily
                            ))
                            #expect(
                                s != .transientDeclaredChild,
                                "no pending request, yet the card says one is waiting: \(s)"
                            )
                        }
                    }
                }
            }
        }
    }

    /// A removed child is still separated from one who never joined — `wasEverInFamily` is
    /// that evidence, and fix 1 must not collapse (7) into (4).
    @Test func aUidHoldingChildWhoWasRemovedStillReadsAsPostRevocation() {
        let s = state(Inputs(
            isAnonymousSession: true,
            hasFirebaseUid: true,
            childSessionState: .unconsentedChild,
            isFamilyApprovalPending: false,
            wasEverInFamily: true
        ))
        #expect(s == .postRevocationChild)
    }

    /// Audit follow-up (2026-08-17): the pending check is consulted BEFORE the cloud-identity
    /// guard. The flag stores the uid it belongs to, so it already carries the evidence that
    /// guard is looking for, and a session whose `hasFirebaseUid` projection has not caught up
    /// must not silently downgrade a real outstanding request to "no request".
    /// `ChildFamilyPromptPolicy` resolves pending first for the same reason.
    @Test func aPendingRequestOutranksAMissingUidProjection() {
        let s = state(Inputs(
            isAnonymousSession: false,
            hasFirebaseUid: false,
            childSessionState: .unconsentedChild,
            isFamilyApprovalPending: true
        ))
        #expect(s == .transientDeclaredChild)
    }

    /// (6) The reported bug. A consented child was shown "Anonymous Account — sign up to sync
    /// your account", which is wrong twice over: the account IS synced, and there is nothing
    /// to sign up for. It gets its own header now.
    @Test func consentedChildGetsItsOwnHeaderNotAnonymousAccount() {
        let s = state(Inputs(
            isAnonymousSession: true,
            hasFirebaseUid: true,
            childSessionState: .consentedChild
        ))
        #expect(s == .consentedChild)

        let p = presentation(s)
        #expect(p.headerKey == "auth_status.child.family_header")
        #expect(p.subtitleKey == "auth_status.child.family_subtitle")
        #expect(p.headerKey != "Anonymous Account")
        // Their data really is in the cloud — the amber warning was misinformation.
        #expect(p.isCloudSynced == true)
        #expect(p.showsSignIn == false)
        #expect(p.showsDeleteAccount == false)
        #expect(p.showsJoinFamily == false)
        #expect(p.childNoticeKey == "child_gate.account.consented_notice")
    }

    /// (7) Membership revoked. `isChildAccount` is sticky server-side, so the session is still
    /// a child — only the family is gone, and `wasEverInFamily` is what separates this from a
    /// child who never joined.
    @Test func postRevocationChild() {
        let s = state(Inputs(
            isAnonymousSession: true,
            hasFirebaseUid: true,
            childSessionState: .unconsentedChild,
            wasEverInFamily: true
        ))
        #expect(s == .postRevocationChild)

        let p = presentation(s)
        #expect(p.headerKey == "auth_status.child.no_family_header")
        #expect(p.subtitleKey == "auth_status.child.no_family_subtitle")
        #expect(p.showsSignIn == false)
        #expect(p.showsJoinFamily == true)
    }

    // MARK: - (8) Detached / reset session

    /// A 13+ or age-unknown session whose anonymous identity this device retired (FR-60(c)).
    /// It renders as an ordinary local account: the retirement is bookkeeping, not something
    /// the player did or needs to be told about.
    @Test func detachedAdultSessionRendersAsALocalAccount() {
        let s = state(Inputs(isIdentityDetached: true, wasEverInFamily: true))
        #expect(s == .detachedAdultSession)
        #expect(presentation(s) == presentation(.localAdultGuest))
    }

    // MARK: - Invariants across the whole matrix

    /// The owner's standing rule, checked against every state at once rather than trusting
    /// each branch: no child session offers a sign-in or an account-deletion affordance.
    ///
    /// A future parent-gated setting could let a guardian sign in on the child's device —
    /// recorded in `AuthenticationStatusPresentation.showsSignIn`, deliberately NOT built. If
    /// that ever lands it will land as its own gated surface, not by loosening this.
    @Test func noChildStateOffersSignInOrAccountDeletion() {
        let childStates: [State] = [
            .localUnconsentedChild, .transientDeclaredChild, .consentedChild, .postRevocationChild
        ]
        for child in childStates {
            let p = presentation(child)
            #expect(p.showsSignIn == false, "\(child) must not offer sign-in")
            #expect(p.showsRegisteredAccountControls == false, "\(child) must not offer account controls")
            #expect(p.showsDeleteAccount == false, "\(child) must not offer account deletion")
        }
    }

    /// Only a registered session gets account controls, and it gets them as a pair.
    @Test func onlyTheRegisteredSessionGetsAccountControls() {
        for s in State.allCases {
            let p = presentation(s)
            #expect(p.showsRegisteredAccountControls == (s == .registeredAdult))
            // Sign-in and sign-out/delete are mutually exclusive by construction.
            #expect(!(p.showsSignIn && p.showsRegisteredAccountControls))
        }
    }

    /// Every state names real copy. A missing key renders as the key itself on device, which
    /// is exactly the kind of thing a state matrix is supposed to make impossible to miss.
    @Test func everyStateHasAHeaderAndASubtitle() {
        for s in State.allCases {
            let p = presentation(s)
            #expect(!p.headerKey.isEmpty, "\(s) has no header")
            #expect(!p.subtitleKey.isEmpty, "\(s) has no subtitle")
            #expect(p.headerKey != p.subtitleKey, "\(s) repeats itself")
        }
    }

    /// The ordering rule that kills the hybrid class of bug: for EVERY combination of the
    /// uid-shaped inputs, a child classification wins. There is no input tuple that lands a
    /// child on an adult headline.
    @Test func childClassificationAlwaysWinsOverEveryUidShapedInput() {
        let childStates: Set<State> = [
            .localUnconsentedChild, .transientDeclaredChild, .consentedChild, .postRevocationChild
        ]
        let childSessions: [ChildRestrictedModeService.ChildSessionState] = [
            .unconsentedChild, .consentedChild
        ]

        for childSession in childSessions {
            for isAnonymous in [true, false] {
                for hasUid in [true, false] {
                    for pending in [true, false] {
                        for everInFamily in [true, false] {
                            for resolved in [true, false] {
                                for detached in [true, false] {
                                    let s = state(Inputs(
                                        isAnonymousSession: isAnonymous,
                                        hasFirebaseUid: hasUid,
                                        childSessionState: childSession,
                                        isFamilyApprovalPending: pending,
                                        isAgeAnswerResolved: resolved,
                                        isIdentityDetached: detached,
                                        wasEverInFamily: everInFamily
                                    ))
                                    #expect(
                                        childStates.contains(s),
                                        "child session \(childSession) classified as \(s)"
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// A registered session is never reclassified as a child, in either direction. Children
    /// have no credentials, so this can only happen through a bug — and if it ever did, the
    /// account controls a real adult depends on must not vanish.
    @Test func aRegisteredSessionIsNeverReclassifiedAsAChild() {
        for childSession in [ChildRestrictedModeService.ChildSessionState.unconsentedChild, .consentedChild] {
            let s = state(Inputs(
                isRegisteredSession: true,
                hasFirebaseUid: true,
                childSessionState: childSession
            ))
            #expect(s == .registeredAdult)
        }
    }
}
