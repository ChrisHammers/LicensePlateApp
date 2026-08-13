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
    static let pendingDeclarationUserIds = "ageGate.pendingDeclarationUserIds"
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

    /// True while the CURRENT identity epoch carries an under-13 answer, i.e. every uid
    /// this epoch provisions still owes a `declareChildRegistration`. Set by the answer,
    /// cleared only when the epoch ends (`clearAnswer`) — delivering one uid's
    /// declaration no longer "spends" the answer for the rest of the epoch.
    var hasPendingChildDeclaration: Bool {
        defaults.bool(forKey: AgeGateStoreKeys.pendingChildDeclaration)
    }

    /// Uids created/upgraded by the under-13 flow whose `declareChildRegistration` has
    /// not been confirmed yet. Declarations and profile-write holds may target ONLY
    /// these uids — a stored answer can never declare or hold any other (pre-existing)
    /// account (incident-1). While a uid is here, its profile write is held (FR-27
    /// ordering).
    ///
    /// A SET, not one slot: a single identity epoch can provision more than one uid
    /// (the deferred guest uid, then a fresh registration uid when an anonymous link
    /// fails). Binding a later uid must never release the earlier uid's hold.
    var pendingDeclarationUserIds: Set<String> {
        Set(defaults.stringArray(forKey: AgeGateStoreKeys.pendingDeclarationUserIds) ?? [])
    }

    /// True when `userId` is a uid this device provisioned under an under-13 answer and
    /// still owes a declaration for.
    func isPendingDeclaration(userId: String?) -> Bool {
        guard let userId, !userId.isEmpty else { return false }
        return pendingDeclarationUserIds.contains(userId)
    }

    /// True while ANY uid on this device still owes a declaration. The device-level
    /// correction (ratchet + stored answer) may never lift while this holds: an
    /// undelivered declaration means the server was never told about a child this
    /// device knows about.
    var hasOutstandingChildDeclaration: Bool {
        !pendingDeclarationUserIds.isEmpty
    }

    /// Uids this device successfully declared as child registrations. Used to bind the
    /// restricted state (FR-28) to the declared identity lineage rather than the whole
    /// device, so a different (adult) sign-in is not sync-held by another user's answer.
    /// Persists across sign-out (protective history; F-7's ratchet consumes it).
    func isDeclaredChildUserId(_ userId: String?) -> Bool {
        guard let userId, !userId.isEmpty else { return false }
        return declaredChildUserIds.contains(userId)
    }

    /// F-7 (FR-39): whether this device ever declared any child registration —
    /// feeds the pre-`MobileAds.start()` device-level stamp.
    var hasDeclaredChildHistory: Bool {
        !declaredChildUserIds.isEmpty
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

    /// Binds the epoch's under-13 answer to a uid the flow just created or upgraded.
    /// EVERY uid an under-13 epoch provisions is bound — not only the first one to
    /// reach a declaration site — so a second provisioning inside the same epoch can
    /// never slip through as an ordinary adult account.
    ///
    /// Scoped by the CURRENT epoch's answer, so an epoch that never answered under-13
    /// (or whose answer was cleared at sign-out) binds nothing: a stale answer still
    /// cannot hold or declare a pre-existing account (incident-1/incident-2).
    func bindPendingDeclaration(toUserId userId: String) {
        guard category == .under13, !userId.isEmpty else { return }
        guard !isDeclaredChildUserId(userId) else { return }
        var ids = pendingDeclarationUserIds
        guard ids.insert(userId).inserted else { return }
        defaults.set(Array(ids), forKey: AgeGateStoreKeys.pendingDeclarationUserIds)
        revision += 1
    }

    /// Binds `userId` if the current epoch requires it and reports whether it still
    /// owes a declaration. This is the whole pre-network decision made by
    /// `FirebaseAuthService.ensureFlowChildDeclaration`, exposed as one call so the
    /// declare-before-write ordering is testable without Firebase.
    @discardableResult
    func bindAndCheckDeclarationOutstanding(forFlowUserId userId: String) -> Bool {
        bindPendingDeclaration(toUserId: userId)
        return isPendingDeclaration(userId: userId)
    }

    /// Marks the under-13 declaration as delivered for `userId` (the declared uid).
    /// The epoch's answer itself is NOT consumed: any further uid the same epoch
    /// provisions must be declared too.
    func markChildDeclarationSent(userId: String) {
        guard !userId.isEmpty else { return }
        var pending = pendingDeclarationUserIds
        pending.remove(userId)
        defaults.set(Array(pending), forKey: AgeGateStoreKeys.pendingDeclarationUserIds)
        var ids = declaredChildUserIds
        ids.insert(userId)
        defaults.set(Array(ids), forKey: AgeGateStoreKeys.declaredChildUserIds)
        revision += 1
    }

    /// COPPA F-8 (FR-5/FR-25 client half): a manager-authorized CORRECTION cleared this
    /// uid's server flag, so the device's under-13 lineage for that uid is no longer
    /// true and must not keep applying child postures until reinstall.
    ///
    /// Authority: only the server can clear `isChildAccount`, and only a family manager
    /// can ask it to (`setFamilyMemberChildStatus` / approval with explicit
    /// `isChild: false`). A FRESH, EXPLICIT server read of `false` for a DECLARED uid is
    /// therefore authoritative — unlike a revocation, where the flag stays TRUE and
    /// nothing here runs. This is the one and only path that removes a uid from the
    /// declared history.
    ///
    /// F-6×F-8 MERGE DECISION (deliberate, not mechanical): this retires ONLY confirmed
    /// `declaredChildUserIds`. It must NEVER drop a uid from `pendingDeclarationUserIds`.
    /// A pending uid is one whose declaration never reached the server, so the server
    /// was never told it is a child — a `false` there is the MISSING DECLARATION, not a
    /// manager's decision, and there is no authority behind it to honor. Dropping it
    /// would release that uid's profile-write hold and let the very account this device
    /// knows to be a child be written out as an adult, permanently.
    func clearDeclaredChildUserId(_ userId: String) {
        guard !userId.isEmpty else { return }
        var ids = declaredChildUserIds
        guard ids.remove(userId) != nil else { return }
        defaults.set(Array(ids), forKey: AgeGateStoreKeys.declaredChildUserIds)
        revision += 1
    }

    /// Device-level half of the same correction: the stored under-13 ANSWER is what
    /// `isLocationRestrictedForCurrentFlow` and the guest-provisioning gate read, and it
    /// is not uid-scoped. It may only be dropped once no child lineage remains on this
    /// device — the caller enforces that (`ChildDeviceCorrectionPolicy`). A `teenAdult`
    /// answer is left alone; there is nothing protective to lift.
    ///
    /// Fail-closed guard (defense in depth, independent of the caller): an undelivered
    /// declaration is an unfulfilled promise about a specific account, so the epoch
    /// answer and the pending set both survive while one is outstanding.
    func clearUnder13AnswerAfterCorrection() {
        guard category == .under13 else { return }
        guard !hasOutstandingChildDeclaration else { return }
        defaults.removeObject(forKey: AgeGateStoreKeys.category)
        defaults.removeObject(forKey: AgeGateStoreKeys.answeredAt)
        defaults.removeObject(forKey: AgeGateStoreKeys.pendingChildDeclaration)
        revision += 1
    }

    /// Clears the epoch-scoped answer. Called on sign-out and account deletion so the
    /// next registration flow asks fresh — a stale answer can never carry over to a new
    /// or different account (incident-2).
    ///
    /// Uid-bound state deliberately survives: `declaredChildUserIds` (protective
    /// history, consumed by F-7's ratchet) AND `pendingDeclarationUserIds` — an
    /// undelivered declaration is a promise this device made about ONE specific
    /// account. Dropping it at sign-out would leave a declared child account with no
    /// child evidence on the device and none on the server, and its next profile write
    /// would sail through as an adult.
    func clearAnswer() {
        defaults.removeObject(forKey: AgeGateStoreKeys.category)
        defaults.removeObject(forKey: AgeGateStoreKeys.answeredAt)
        defaults.removeObject(forKey: AgeGateStoreKeys.pendingChildDeclaration)
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

/// Pure decision behind `FirebaseAuthService.saveUserDataToFirestore`: the ONLY accounts
/// whose profile write can ever be held are the uids a registration flow provisioned
/// while their under-13 declaration is still outstanding. Existing accounts are never
/// held and can never be declared by a stored answer (incident-1 regression: the policy
/// takes no category/answer input at all — an unbound stale answer cannot hold or
/// declare anything).
enum AgeGateProfileWritePolicy {
    static func isProfileWriteHeld(userUid: String?, pendingDeclarationUserIds: Set<String>) -> Bool {
        guard let userUid, !userUid.isEmpty else { return false }
        return pendingDeclarationUserIds.contains(userUid)
    }
}

// MARK: - users/{uid} document write guard (FR-27 ordering, all writers)

/// Every Firestore writer that can CREATE `users/{uid}` must pass this, not just the
/// profile write. `setData(merge: true)` creates the document when it is absent, so a
/// preference write (notification prefs, game defaults, participation defaults) racing
/// ahead of the declaration would provision a FLAGLESS `users/{uid}` for a child — the
/// exact shape that reads back as `isChildAccount` absent → not-a-child, turns on ads,
/// and (post-F-8) trips the manager-correction path that erases the device's under-13
/// lineage for good.
///
/// The declare-before-write choke point (`createNewUserFromFirebase` /
/// `saveUserDataToFirestore`) is the only writer permitted to bring the document into
/// existence; everyone else waits behind the same hold.
enum UserDocumentWritePolicy {
    /// Held for exactly the uids that still owe a child declaration.
    static func isWriteHeld(userId: String?, pendingDeclarationUserIds: Set<String>) -> Bool {
        AgeGateProfileWritePolicy.isProfileWriteHeld(
            userUid: userId,
            pendingDeclarationUserIds: pendingDeclarationUserIds
        )
    }
}

/// Thrown by `users/{uid}` writers that are held behind an outstanding child
/// declaration. Callers surface it like any other write failure and retry later; the
/// declaration itself is retried by the choke point.
struct UserDocumentWriteHeldError: LocalizedError {
    let userId: String

    var errorDescription: String? {
        "Profile write held pending child registration for \(userId)."
    }
}

// MARK: - Child-flag ingest policy (COPPA F-7, FR-19 asymmetric trust)

/// FR-19 requires that only THIS SESSION'S FRESH SERVER READ of `users/{uid}` may
/// resolve the child projection. A latency-compensated snapshot (served from the local
/// cache, or reflecting our own not-yet-acknowledged write) is not that read: for a
/// brand-new uid it shows the fields the client just wrote and nothing else, so a
/// missing `isChildAccount` there means "unknown", not "adult". Such snapshots leave
/// the tri-state projection nil, which keeps the session held (fail-closed).
enum ChildFlagIngestPolicy {
    static func mayIngest(isFromCache: Bool, hasPendingWrites: Bool) -> Bool {
        !isFromCache && !hasPendingWrites
    }
}
