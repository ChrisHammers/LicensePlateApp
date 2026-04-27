//
//  AccountState.swift
//  LicensePlateApp
//
//  Centralized account-state classification for entitlement and UI-access policy.
//

import Foundation
import FirebaseAuth

enum AccountState: Equatable {
    case localGuest
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
        return firebaseUser.isAnonymous ? .firebaseAnonymous : .signedIn
    }
}
