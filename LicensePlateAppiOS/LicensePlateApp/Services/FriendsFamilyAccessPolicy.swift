//
//  FriendsFamilyAccessPolicy.swift
//  LicensePlateApp
//
//  UI and search access policy for Friends & Family features.
//

import Foundation
import FirebaseAuth

@MainActor
final class FriendsFamilyAccessPolicy {
    static let shared = FriendsFamilyAccessPolicy()

    private let accountStateProvider: AccountStateProviding

    init(accountStateProvider: AccountStateProviding = FirebaseAccountStateProvider.shared) {
        self.accountStateProvider = accountStateProvider
    }

    func canUseFriendsAndFamily(for user: AppUser?) -> Bool {
        !accountStateProvider.currentAccountState(for: user).isGuestLike
    }

    /// Throws before Friends & Family Cloud Function calls when the viewer lacks a registered account.
    func validateFriendsFamilyCallableAccess(for user: AppUser?) throws {
        guard Auth.auth().currentUser != nil else {
            throw NSError(
                domain: "FriendsFamilyAccessPolicy",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "You are not signed in. Sign in and try again.".localized]
            )
        }
        guard canUseFriendsAndFamily(for: user) else {
            throw NSError(
                domain: "FriendsFamilyAccessPolicy",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: FriendsFamilyCallableErrors.guestBlockedMessage]
            )
        }
    }

    /// COPPA F-18 (FR-60(b)): the two CONSENT EXITS — `redeemShareCode` and
    /// `respondToFamilyInvite_UserStep` — accept a declared child's anonymous session.
    ///
    /// Under the local-first model a child provisions at share-code entry and is still
    /// anonymous when the redeem call goes out, so the ordinary registered-account gate would
    /// dead-end the only path a child has to consent. The server carve-out
    /// (`assertRegisteredAccountOrDeclaredChild`) is the authority; this is the pre-emptive
    /// client half, and it stays strictly narrower — it opens for a declared CHILD session
    /// only, never for an ordinary anonymous guest.
    ///
    /// Device pass 2026-08-17 (bug 1): it used to open with an unconditional
    /// `guard Auth.auth().currentUser != nil else { throw "You are not signed in…" }`, ahead of
    /// the child branch. That inverted the whole point of the exit. Under FR-60(a) an
    /// under-13-flow session has NO Firebase session by design — the uid is minted at this very
    /// moment by `provisionIdentityForConsentSeekingRedemptionIfNeeded` — and a self-healed
    /// child was signed out by the FR-60(c) detach seconds earlier. So the one population the
    /// exit exists for was the one it rejected, with the one instruction they cannot follow:
    /// FR-60(e) leaves a child with no account to sign in to.
    func validateConsentExitCallableAccess(for user: AppUser?) throws {
        let decision = Self.consentExitAccess(
            accountState: accountStateProvider.currentAccountState(for: user),
            hasFirebaseSession: Auth.auth().currentUser != nil,
            isDeclaredChildSession: ChildRestrictedModeService.shared.isChildAccountSession
        )
        switch decision {
        case .allowed:
            return
        case .childProvisioningIncomplete:
            // NOT an authorization failure and never phrased as one. The session is valid for
            // this exit; the uid simply is not there yet, which is a retryable local condition
            // (offline, App Check, a mint that failed). Same copy `AuthError.childDeclarationPending`
            // uses, so the child sees one message for one condition.
            throw NSError(
                domain: "FriendsFamilyAccessPolicy",
                code: 409,
                userInfo: [NSLocalizedDescriptionKey: FriendsFamilyCallableErrors.childSetupIncompleteMessage]
            )
        case .blockedNeedsSignIn:
            throw NSError(
                domain: "FriendsFamilyAccessPolicy",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "You are not signed in. Sign in and try again.".localized]
            )
        case .blockedNeedsRegistration:
            throw NSError(
                domain: "FriendsFamilyAccessPolicy",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: FriendsFamilyCallableErrors.guestBlockedMessage]
            )
        }
    }

    /// Testable gate for callable access without touching Firebase Auth singleton.
    ///
    /// Deliberately UNCHANGED and deliberately NOT the consent-exit rule: friends, search and
    /// family administration stay closed to guest-like sessions, and an adult guest with no
    /// session still needs to sign up. The two gates are separate functions precisely so a
    /// widening of the consent exit can never widen this one.
    static func blocksCallableAccess(
        accountState: AccountState,
        hasFirebaseSession: Bool
    ) -> Bool {
        guard hasFirebaseSession else { return true }
        return accountState.isGuestLike
    }

    /// What the consent exit does with a session, and WHY — three outcomes, not two, because
    /// "no Firebase session" means opposite things for the two populations that reach here.
    enum ConsentExitAccess: Equatable {
        /// Pass through to the callable; the server carve-out is the authority.
        case allowed
        /// An under-13-flow session whose uid has not been minted yet. VALID for this exit —
        /// the caller owes it a provisioning pass, and the player owes nothing but a retry.
        case childProvisioningIncomplete
        /// No session and no child lineage: an adult who is genuinely signed out.
        case blockedNeedsSignIn
        /// A live anonymous session with no child lineage: an ordinary guest.
        case blockedNeedsRegistration
    }

    /// Testable twin of `validateConsentExitCallableAccess`.
    ///
    /// The contract, stated so it cannot drift back into a comment in two ViewModels:
    /// **an under-13-flow session with no Firebase session is VALID for the consent exit.**
    /// FR-60(b)'s ordering (mint → bind → declare → redeem) is what turns it into `.allowed`,
    /// and the caller that skips the mint gets `.childProvisioningIncomplete`, which names the
    /// missing step instead of blaming the child for a sign-in they cannot perform.
    static func consentExitAccess(
        accountState: AccountState,
        hasFirebaseSession: Bool,
        isDeclaredChildSession: Bool
    ) -> ConsentExitAccess {
        // The child branch runs FIRST — this ordering is the fix. A declared child is the
        // population this exit exists for, in both of its states.
        if isDeclaredChildSession {
            return hasFirebaseSession ? .allowed : .childProvisioningIncomplete
        }
        guard hasFirebaseSession else { return .blockedNeedsSignIn }
        return accountState.isGuestLike ? .blockedNeedsRegistration : .allowed
    }

    /// Bool projection of `consentExitAccess`, kept for the acceptance suites that read the
    /// gate as "does this session get through?".
    static func blocksConsentExitAccess(
        accountState: AccountState,
        hasFirebaseSession: Bool,
        isDeclaredChildSession: Bool
    ) -> Bool {
        consentExitAccess(
            accountState: accountState,
            hasFirebaseSession: hasFirebaseSession,
            isDeclaredChildSession: isDeclaredChildSession
        ) != .allowed
    }
}
