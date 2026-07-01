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

    /// Testable gate for callable access without touching Firebase Auth singleton.
    static func blocksCallableAccess(
        accountState: AccountState,
        hasFirebaseSession: Bool
    ) -> Bool {
        guard hasFirebaseSession else { return true }
        return accountState.isGuestLike
    }
}
