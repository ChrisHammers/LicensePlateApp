//
//  AccountState.swift
//  LicensePlateApp
//
//  Centralized account-state classification for entitlement and UI-access policy.
//

import Foundation
import FirebaseAuth

/// Item 11 of SRS 3.1.1 (2026-09-11): the ONE client answer to "does this session have
/// credentials its owner can sign back in with?". A session is credentialed only when it is
/// non-anonymous AND has at least one provider. A CUSTOM-TOKEN session — the FR-84 transferred
/// child — is non-anonymous with NO provider, and every site that read `!isAnonymous` as
/// "registered" showed that child a Signed-In adult's profile and offered their account as a
/// saved user after a reinstall. This is the boundary `firestore.rules`' `isRegisteredAccount()`
/// and `callableAuth.ts` already draw (anonymous and custom are both uncredentialed there).
enum SessionCredentialPolicy {
    static func isCredentialed(isAnonymous: Bool, providerCount: Int) -> Bool {
        !isAnonymous && providerCount > 0
    }
}

/// Whether onboarding may offer the session restored from the Keychain as "Continue as <name>".
/// Only a credentialed session is anybody's to continue (item 11), and never under an under-13
/// device answer (owner 2026-09-12: "putting a child date still shows the old user as
/// something you can select") — OD-9(iv): device child history overrides.
enum SavedAccountOfferPolicy {
    static func mayOfferRestoredAccount(isCredentialedSession: Bool, deviceAnswer: AgeGateCategory?) -> Bool {
        isCredentialedSession && deviceAnswer != .under13
    }
}

enum AccountState: Equatable {
    case localGuest
    /// A cloud identity without credentials: an anonymous guest OR a custom-token
    /// (transferred child) session. Guest-like for every entitlement/UI-access decision.
    case firebaseAnonymous
    case signedIn

    var isGuestLike: Bool {
        switch self {
        case .localGuest, .firebaseAnonymous:
            return true
        case .signedIn:
            return false
        }
    }

    /// True when the user upgraded from guest/anonymous to a registered account.
    static func shouldReportAuthSuccess(from previous: AccountState, to current: AccountState) -> Bool {
        previous.isGuestLike && current == .signedIn
    }
}

@MainActor
protocol AccountStateProviding: AnyObject {
    func currentAccountState(for user: AppUser?) -> AccountState
}

@MainActor
final class FirebaseAccountStateProvider: AccountStateProviding {
    static let shared = FirebaseAccountStateProvider()

    private init() {}

    func currentAccountState(for user: AppUser?) -> AccountState {
        guard let firebaseUser = Auth.auth().currentUser else {
            return .localGuest
        }
        return SessionCredentialPolicy.isCredentialed(
            isAnonymous: firebaseUser.isAnonymous,
            providerCount: firebaseUser.providerData.count
        ) ? .signedIn : .firebaseAnonymous
    }
}
