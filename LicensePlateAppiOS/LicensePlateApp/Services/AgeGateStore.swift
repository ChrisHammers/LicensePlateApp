//
//  AgeGateStore.swift
//  LicensePlateApp
//
//  COPPA F-6 (FR-27 amended, D-3): device-local record of the neutral age screen's
//  outcome. Stores ONLY the derived category and the answer timestamp — never the
//  birth year itself (data minimization). No SwiftData involvement (frozen schema).
//
//  F-7 consumes `category` / `isResolved` / `answeredAt` for ad/analytics postures;
//  this store deliberately contains no ad, analytics, location, or paywall logic.
//

import Foundation
import Combine

/// Derived age category from the neutral age screen. The birth year is discarded
/// immediately after derivation and is never persisted or logged.
enum AgeGateCategory: String {
    case under13 = "under13"
    case teenAdult = "teen_adult"
}

enum AgeGateStoreKeys {
    static let category = "ageGate.category"
    static let answeredAt = "ageGate.answeredAt"
    static let pendingChildDeclaration = "ageGate.pendingChildDeclaration"
    static let pendingDeclarationUserId = "ageGate.pendingDeclarationUserId"
    static let declaredChildUserIds = "ageGate.declaredChildUserIds"
}

/// UserDefaults-backed age-gate state (no SwiftData; follows `FirstSessionState` idiom).
@MainActor
final class AgeGateStore: ObservableObject {
    static let shared = AgeGateStore()

    /// Bumped on every mutation so SwiftUI surfaces can react (DeferredProfileSetupStore idiom).
    @Published private(set) var revision = 0

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Derivation (FR-27)

    /// Neutral year-only classification: with only a birth year, the person's age is
    /// `currentYear - birthYear` at most. A difference below 13 means the person cannot
    /// yet be 13 in `currentYear`, so they are classified under 13.
    static func category(forBirthYear birthYear: Int, currentYear: Int) -> AgeGateCategory {
        (currentYear - birthYear) < 13 ? .under13 : .teenAdult
    }

    // MARK: - Read surface (consumed by F-7)

    var category: AgeGateCategory? {
        guard let raw = defaults.string(forKey: AgeGateStoreKeys.category) else { return nil }
        return AgeGateCategory(rawValue: raw)
    }

    var answeredAt: Date? {
        let interval = defaults.double(forKey: AgeGateStoreKeys.answeredAt)
        return interval > 0 ? Date(timeIntervalSince1970: interval) : nil
    }

    /// True once the neutral age screen has been answered on this device.
    var isResolved: Bool {
        category != nil
    }

    /// True while an under-13 answer from the current flow has not yet been bound to
    /// the uid that flow creates (offline first launch, or no auth uid exists yet).
    var hasPendingChildDeclaration: Bool {
        defaults.bool(forKey: AgeGateStoreKeys.pendingChildDeclaration)
    }

    /// The uid created/upgraded by the flow that answered under-13, whose
    /// `declareChildRegistration` has not yet been confirmed. Declarations may target
    /// ONLY this uid — a stored answer can never declare any other (pre-existing)
    /// account. While set, that uid's first profile write is held (FR-27 ordering).
    var pendingDeclarationUserId: String? {
        defaults.string(forKey: AgeGateStoreKeys.pendingDeclarationUserId)
    }

    /// Uids this device successfully declared as child registrations. Used to bind the
    /// restricted state (FR-28) to the declared identity lineage rather than the whole
    /// device, so a different (adult) sign-in is not sync-held by another user's answer.
    /// Persists across sign-out (protective history; F-7's ratchet consumes it).
    func isDeclaredChildUserId(_ userId: String?) -> Bool {
        guard let userId, !userId.isEmpty else { return false }
        return declaredChildUserIds.contains(userId)
    }

    private var declaredChildUserIds: Set<String> {
        Set(defaults.stringArray(forKey: AgeGateStoreKeys.declaredChildUserIds) ?? [])
    }

    // MARK: - Mutations

    /// Records the derived answer for the current flow. Protective direction only: an
    /// existing `under13` answer is never overwritten by a later `teenAdult` answer
    /// within the same flow lifetime (clearing happens at sign-out; parent correction
    /// flows land in F-8).
    func recordAnswer(_ newCategory: AgeGateCategory, at date: Date = .now) {
        if category == .under13, newCategory == .teenAdult {
            return
        }
        defaults.set(newCategory.rawValue, forKey: AgeGateStoreKeys.category)
        defaults.set(date.timeIntervalSince1970, forKey: AgeGateStoreKeys.answeredAt)
        if newCategory == .under13 {
            defaults.set(true, forKey: AgeGateStoreKeys.pendingChildDeclaration)
        }
        revision += 1
    }

    /// Binds the flow's outstanding under-13 answer to the uid that flow just created
    /// or upgraded. From here on the declaration can target only this uid.
    func bindPendingDeclaration(toUserId userId: String) {
        guard hasPendingChildDeclaration, !userId.isEmpty else { return }
        defaults.set(userId, forKey: AgeGateStoreKeys.pendingDeclarationUserId)
        revision += 1
    }

    /// Marks the under-13 declaration as delivered for `userId` (the declared uid).
    func markChildDeclarationSent(userId: String) {
        defaults.set(false, forKey: AgeGateStoreKeys.pendingChildDeclaration)
        defaults.removeObject(forKey: AgeGateStoreKeys.pendingDeclarationUserId)
        if !userId.isEmpty {
            var ids = declaredChildUserIds
            ids.insert(userId)
            defaults.set(Array(ids), forKey: AgeGateStoreKeys.declaredChildUserIds)
        }
        revision += 1
    }

    /// Clears the stored answer and any unfinished declaration intent. Called on
    /// sign-out and account deletion so the next registration flow asks fresh —
    /// a stale answer can never carry over to a new or different account.
    /// `declaredChildUserIds` history is uid-bound and deliberately survives.
    func clearAnswer() {
        defaults.removeObject(forKey: AgeGateStoreKeys.category)
        defaults.removeObject(forKey: AgeGateStoreKeys.answeredAt)
        defaults.removeObject(forKey: AgeGateStoreKeys.pendingChildDeclaration)
        defaults.removeObject(forKey: AgeGateStoreKeys.pendingDeclarationUserId)
        revision += 1
    }
}

// MARK: - Guest provisioning policy (FR-27 acceptance seam)

/// Pure rules for anonymous-identity creation. The age answer is scoped to an
/// IDENTITY EPOCH: sign-out and account deletion clear it, so a stored answer never
/// carries across identities — and no NEW anonymous uid is ever provisioned without
/// an answer for the current epoch. First launch and post-sign-out guest rebirth are
/// the same case; signed-in / keychain-restored sessions (uid exists) never gate.
enum GuestProvisioningPolicy {
    /// Gate on `FirebaseAuthService.signInAnonymously` — the single place fresh
    /// anonymous uids are created.
    static func mayCreateAnonymousIdentity(isResolved: Bool) -> Bool {
        isResolved
    }

    /// Whether the current session must pass the age screen before guest provisioning.
    static func requiresAgeGate(hasFirebaseUid: Bool, isResolved: Bool) -> Bool {
        !hasFirebaseUid && !isResolved
    }
}

// MARK: - Profile-write policy (FR-27 acceptance seam)

/// Pure decision behind `FirebaseAuthService.saveUserDataToFirestore`: the ONLY account
/// whose profile write can ever be held is the uid a registration flow created while
/// its under-13 declaration is still outstanding. Existing accounts are never held and
/// can never be declared by a stored answer (incident-1 regression: the policy takes no
/// category/answer input at all — an unbound stale answer cannot hold or declare
/// anything).
enum AgeGateProfileWritePolicy {
    static func isProfileWriteHeld(userUid: String?, pendingDeclarationUserId: String?) -> Bool {
        guard let pendingUid = pendingDeclarationUserId, let userUid else { return false }
        return pendingUid == userUid
    }
}
