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
    func validateConsentExitCallableAccess(for user: AppUser?) throws {
        guard Auth.auth().currentUser != nil else {
            throw NSError(
                domain: "FriendsFamilyAccessPolicy",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "You are not signed in. Sign in and try again.".localized]
            )
        }
        let blocked = Self.blocksConsentExitAccess(
            accountState: accountStateProvider.currentAccountState(for: user),
            hasFirebaseSession: true,
            isDeclaredChildSession: ChildRestrictedModeService.shared.isChildAccountSession
        )
        guard !blocked else {
            throw NSError(
                domain: "FriendsFamilyAccessPolicy",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: FriendsFamilyCallableErrors.guestBlockedMessage]
            )
        }
    }

    /// Testable gate for callable access without touching Firebase Auth singleton.
    static func blocksCallableAccess(
        accountState: AccountState,
        hasFirebaseSession: Bool
    ) -> Bool {
        guard hasFirebaseSession else { return true }
        return accountState.isGuestLike
    }

    /// Testable twin of `validateConsentExitCallableAccess`. A live Firebase session is still
    /// mandatory — a uid-less local child is blocked here, which is correct: the redemption
    /// flow provisions FIRST and only then reaches this gate.
    static func blocksConsentExitAccess(
        accountState: AccountState,
        hasFirebaseSession: Bool,
        isDeclaredChildSession: Bool
    ) -> Bool {
        guard hasFirebaseSession else { return true }
        if isDeclaredChildSession { return false }
        return accountState.isGuestLike
    }
}
