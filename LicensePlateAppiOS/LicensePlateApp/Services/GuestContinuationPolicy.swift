//
//  GuestContinuationPolicy.swift
//  LicensePlateApp
//
//  Decides whether "Continue as Guest" may mint a fresh anonymous Auth session.
//

import Foundation

enum GuestContinuationPolicy {
    /// Only leave a restored **signed-in** account by creating a new anonymous session.
    /// Already guest-like identities must keep their UID so local trips/XP stay visible.
    static func shouldCreateFreshAnonymousSession(accountState: AccountState) -> Bool {
        !accountState.isGuestLike
    }
}
