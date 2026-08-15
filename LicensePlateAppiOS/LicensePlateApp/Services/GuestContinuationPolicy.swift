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

// MARK: - Anonymous → registered upgrade (v2.1 §11.4 / FR-27 / FR-60(d))

/// Pure rules behind `FirebaseAuthService.createAccount`.
///
/// v2.1 §11.4 specifies registration as a **link**: the guest's anonymous uid survives the
/// upgrade, so every local row already keyed to it stays owned by the same player and the
/// server still recognises `trip_sessions/{id}.createdBy` as the caller. The two ways that
/// guarantee gets lost are encoded here instead of being left to the shape of a `do/catch`:
///
///  1. **What may fall back to a fresh account.** Only a credential conflict — this email
///     already belongs to some other account — is a failure that a *different* account could
///     resolve. A transient failure (network, App Check, backend) must never fork the
///     identity: the anonymous session is still perfectly good and the user can just retry.
///     Falling back on *any* error also swept up errors raised AFTER a SUCCESSFUL link (the
///     profile write), which tore down a linked session and registered a second account.
///  2. **When the local play identity has to be carried.** Any path that settles on a uid
///     other than the one the local gameplay rows name — the fresh-account fallback, and
///     registration from a session that never held an anonymous uid — must move that history
///     explicitly. `signInAnonymously` is not involved on those paths, so FR-60(d)'s rebind
///     does not run on its own, and the rows keep naming an identity the app no longer
///     resolves: trips vanish from `loadActiveSessions(userId:)`, the active-trip limit
///     resets, and `publishTripCanonicalState` is refused because the payload's `createdBy`
///     is no longer the caller.
enum AnonymousUpgradePolicy {
    /// `AuthErrorCode` raw values meaning "this credential already belongs to an account":
    /// `emailAlreadyInUse` (17007), `providerAlreadyLinked` (17015),
    /// `credentialAlreadyInUse` (17025).
    static let credentialConflictErrorCodes: Set<Int> = [17007, 17015, 17025]

    /// Whether a failed `link(with:)` may be retried as a brand-new account.
    static func shouldFallBackToFreshAccount(linkErrorCode: Int) -> Bool {
        credentialConflictErrorCodes.contains(linkErrorCode)
    }

    /// True when the uid registration settled on is NOT the identity this device's local
    /// gameplay rows are keyed to, so `LocalPlayIdentityRepository` has work to do.
    static func requiresLocalPlayIdentityRebind(
        previousPlayIdentity: String?,
        registeredUid: String
    ) -> Bool {
        LocalPlayIdentityRebindPolicy.shouldRebind(
            previousUserId: previousPlayIdentity,
            newUserId: registeredUid
        )
    }
}

// MARK: - Promoting the local-first player onto a new uid (FR-60(b))

/// Whether a brand-new `users/{uid}` being created for `firebaseUser` is the PROMOTION of
/// this device's own unprovisioned local player — the FR-60 child finally reaching share-code
/// entry — rather than a genuinely new or newly-hydrated account.
///
/// It decides whether the profile the player already chose (avatar, username) comes with them.
/// Before FR-60 there was nothing to carry: the local `AppUser` was a device-default username
/// and a random avatar that existed for milliseconds. Now the child picks an avatar in
/// onboarding and plays for days, and the uid arrives on top of a real profile — so creating
/// the account with defaults publishes a stranger to the family they are asking to join.
///
/// Both conditions are load-bearing:
///  * **anonymous** — a registered sign-in must never inherit a guest's identity off the same
///    device. Only the local-first promotion path mints an anonymous uid for an existing
///    local player.
///  * **no uid on the local player** — the local player must actually be unprovisioned. A
///    player who already has a uid is not being promoted; some other account is being loaded.
enum LocalPlayerPromotionPolicy {
    static func carriesLocalProfile(
        isAnonymousSession: Bool,
        localPlayerHasFirebaseUid: Bool
    ) -> Bool {
        isAnonymousSession && !localPlayerHasFirebaseUid
    }
}
