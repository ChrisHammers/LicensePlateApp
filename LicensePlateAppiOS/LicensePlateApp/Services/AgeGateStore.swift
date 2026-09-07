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
    static let detachedIdentityUserIds = "ageGate.detachedIdentityUserIds"
    /// FR-110(a): the age-out marker. Device-scoped PROTECTION state like the declared-uid
    /// history — deliberately NOT cleared by `clearAnswer()` or a correction, because the
    /// inputs that produced it are discarded and can never be backfilled.
    static let ageOutYearMonth = "ageGate.ageOutYearMonth"
    /// FR-74 (F-30) retry-deterrence marker: the instant an under-13 answer's cooldown
    /// lapses, as `timeIntervalSince1970`. Armed by `clearAnswer()` when the answer it
    /// ends was `under13` — i.e. an under-13 answer leaves protective residue behind on
    /// the DEVICE even after the epoch that gave it is over.
    ///
    /// Placement is deliberate (SRS v3.1 note): this is NOT a fourth ad-hoc device store.
    /// It lives in `AgeGateStore`'s existing key family beside the epoch answer, the
    /// declared-uid history and the detached-uid ratchet, so the whole precedence surface
    /// stays one document. Device-local, never synced, never written to Firestore.
    static let under13CooldownUntil = "ageGate.under13CooldownUntil"
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

    // MARK: - Derivation (FR-27, amended FR-55 v3.7: exact boundary from month + year)

    /// Exact-boundary classification: `.teenAdult` only when the 13th-birthday MONTH is
    /// strictly in the past — `(currentYear, currentMonth) > (birthYear + 13, birthMonth)`.
    ///
    /// The residual ambiguity is NOT eliminated, only shrunk — and still resolved
    /// protectively: the day is never asked for (deliberate minimization), so a person in
    /// their birthday month may be 12 or 13, and that cohort classifies `.under13`.
    /// Month+year shrinks the ambiguous population from roughly half a birth-year cohort
    /// to one twelfth of one; the conservative tiebreak remains load-bearing and MUST NOT
    /// be "simplified" into an exact comparison by a future implementer.
    ///
    /// BOUNDARY SYMMETRY (FR-55 ↔ AGEOUT FR-110/FR-111, verified, do not touch): this
    /// gate rule (birthday month ⇒ still `.under13`) and AGEOUT's detection rule
    /// (`ageOutYearMonth < currentYearMonth`, STRICT) agree exactly — born 2014-03 ⇒
    /// marker 202703: Feb 2027 child, MARCH 2027 STILL CHILD, Apr 2027 ages out.
    /// Protection runs through the whole birthday month at both ends; flipping either
    /// comparison ages a child out during a month they may still be 12.
    static func category(
        forBirthMonth birthMonth: Int,
        birthYear: Int,
        currentMonth: Int,
        currentYear: Int
    ) -> AgeGateCategory {
        currentYear * 100 + currentMonth
            > ageOutYearMonth(forBirthMonth: birthMonth, birthYear: birthYear)
            ? .teenAdult
            : .under13
    }

    /// FR-110(a): the age-out marker — `(birthYear + 13) * 100 + birthMonth` (born
    /// 2014-03 ⇒ `202703`), one comparable integer. Honest framing, per the SRS: this is
    /// losslessly reversible to the birth year-month (subtract 1300), so persisting it is
    /// EQUIVALENT to storing month+year — what is actually minimized is the DAY, which is
    /// never asked for. The reversibility is deliberate and load-bearing (FR-117 shows a
    /// parent the date being confirmed); a year-month is not an identifier.
    static func ageOutYearMonth(forBirthMonth birthMonth: Int, birthYear: Int) -> Int {
        (birthYear + 13) * 100 + birthMonth
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

    /// FR-110(a): the persisted age-out marker for this device's under-13 lineage, or
    /// `nil` when no under-13 answer with birth data has ever been recorded here.
    /// Survives `clearAnswer()` and correction — see the key's doc comment.
    var ageOutYearMonth: Int? {
        let value = defaults.integer(forKey: AgeGateStoreKeys.ageOutYearMonth)
        return value > 0 ? value : nil
    }

    /// True once the neutral age screen has been answered on this device.
    var isResolved: Bool {
        category != nil
    }

    // MARK: - FR-74 retry deterrence (F-30)

    /// The instant this device's under-13 retry cooldown lapses, or `nil` when no
    /// under-13 answer has ever been ended here. See `AgeGateRetryCooldownPolicy`.
    var under13CooldownUntil: Date? {
        let interval = defaults.double(forKey: AgeGateStoreKeys.under13CooldownUntil)
        return interval > 0 ? Date(timeIntervalSince1970: interval) : nil
    }

    /// FR-74: whether the deterrence window is open right now. Time-bounded by
    /// construction — an expired marker reads inactive without being rewritten, so an
    /// offline device cannot be held past the window by a missed cleanup pass.
    func isUnder13RetryCooldownActive(now: Date = .now) -> Bool {
        AgeGateRetryCooldownPolicy.isCooldownActive(until: under13CooldownUntil, now: now)
    }

    /// FR-74(b): a 13+ answer given while the deterrence window is open. The account
    /// still provisions; the SESSION posture is held at the `.ratchetedAnonymous`
    /// equivalent until the window lapses (`ChildSessionPosturePolicy`).
    func isUnder13RetryCooldownHeld(now: Date = .now) -> Bool {
        AgeGateRetryCooldownPolicy.holdsSessionPosture(
            category: category,
            isCooldownActive: isUnder13RetryCooldownActive(now: now)
        )
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

    var declaredChildUserIds: Set<String> {
        Set(defaults.stringArray(forKey: AgeGateStoreKeys.declaredChildUserIds) ?? [])
    }

    /// FR-60(c) zombie guard — uids this device has DETACHED because the identity no longer
    /// exists server-side (a captain declined, or a parent used remove-and-delete, and the
    /// cleanup removed both the Auth user and `users/{uid}`).
    ///
    /// The device keeps the uid in three places the server cannot reach — the Keychain Auth
    /// session, `AppUser.firebaseUID`, and `declaredChildUserIds` — so without this the dead
    /// uid stays addressable: `updateLoginTimestampsInFirestore` and the `appPrefs` writers
    /// both use `setData(merge: true)`, which CREATES the document, and the resurrected doc
    /// cannot carry `isChildAccount` (rules forbid it on create), so it reads back as an
    /// adult. Once an identity is detached, no writer on this device may address it again.
    ///
    /// Distinct from `pendingDeclarationUserIds` on purpose: that set holds a write until a
    /// declaration lands and then RELEASES it, which is exactly why it never covered this —
    /// a deleted account's declaration had already landed.
    var detachedIdentityUserIds: Set<String> {
        Set(defaults.stringArray(forKey: AgeGateStoreKeys.detachedIdentityUserIds) ?? [])
    }

    /// True when `userId` is an identity this device has retired. Read by every self-doc
    /// writer and by the session bootstrap, which must never re-adopt a retired uid — not
    /// even when a `users/{uid}` document exists for it again (a resurrection write is
    /// exactly how the deletion stopped being detectable, see
    /// `DetachedIdentityDetectionPolicy`).
    func isIdentityDetached(_ userId: String?) -> Bool {
        guard let userId, !userId.isEmpty else { return false }
        return detachedIdentityUserIds.contains(userId)
    }

    // MARK: - Mutations

    /// Records the derived answer for the current flow. Protective direction only: an
    /// existing `under13` answer is never overwritten by a later `teenAdult` answer
    /// within the same flow lifetime (clearing happens at sign-out; parent correction
    /// flows land in F-8).
    func recordAnswer(
        _ newCategory: AgeGateCategory,
        ageOutYearMonth: Int? = nil,
        at date: Date = .now
    ) {
        if category == .under13, newCategory == .teenAdult {
            return
        }
        defaults.set(newCategory.rawValue, forKey: AgeGateStoreKeys.category)
        defaults.set(date.timeIntervalSince1970, forKey: AgeGateStoreKeys.answeredAt)
        if newCategory == .under13 {
            defaults.set(true, forKey: AgeGateStoreKeys.pendingChildDeclaration)
            // FR-110(a): capture the age-out marker while the inputs still exist —
            // the gate's submit is the ONLY moment they do. A marker-less under-13
            // call (e.g. FR-26's re-assert, which has no birth data) leaves any
            // existing marker in place rather than erasing it.
            if let ageOutYearMonth {
                defaults.set(ageOutYearMonth, forKey: AgeGateStoreKeys.ageOutYearMonth)
            }
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

    /// Records that this device has stopped using `userId` as an identity, because the
    /// account behind it is gone server-side (FR-60(c) decline/deletion cleanup) or because
    /// the session was a restored identity this device's current age answer does not own.
    ///
    /// Never removed. A detached anonymous uid is unrecoverable by construction — it has no
    /// credentials — so there is no future in which writing to it again is correct, and the
    /// set stays a one-way protective ratchet like `declaredChildUserIds`.
    func markIdentityDetached(userId: String) {
        guard !userId.isEmpty else { return }
        var ids = detachedIdentityUserIds
        guard ids.insert(userId).inserted else { return }
        defaults.set(Array(ids), forKey: AgeGateStoreKeys.detachedIdentityUserIds)
        revision += 1
    }

    // MARK: - Consent-seeking window (FR-60(b)/(d), FR-26 re-admission)

    /// Uids that are PURSUING ADMISSION to a family at this instant — the open half of
    /// `UnconsentedChildCloudWritePolicy`'s window.
    ///
    /// In memory only, and deliberately so: the window is scoped to one share-code attempt by
    /// one user gesture. Persisting it would let a killed app leave it latched open forever,
    /// which is the cloud-footprint bug the hold exists to prevent.
    ///
    /// It lives HERE rather than on `FirebaseAuthService` because both write choke points need
    /// it — `saveUserDataToFirestore` (service layer) and `UserRepository.assertMayWriteUserDocument`
    /// (repository layer) — and the repository could only ever answer `false` for a private
    /// field on the service. One authority, consulted by both, is what makes the window mean
    /// the same thing at every hold.
    private var consentSeekingUserIds: Set<String> = []

    func isSeekingConsent(userId: String?) -> Bool {
        guard let userId, !userId.isEmpty else { return false }
        return consentSeekingUserIds.contains(userId)
    }

    /// Opens the window for `userId`. Idempotent; the matching `endConsentSeeking` closes it.
    func beginConsentSeeking(userId: String) {
        guard !userId.isEmpty else { return }
        guard consentSeekingUserIds.insert(userId).inserted else { return }
        revision += 1
    }

    func endConsentSeeking(userId: String) {
        guard consentSeekingUserIds.remove(userId) != nil else { return }
        revision += 1
    }

    /// Closes the window for every uid. Called when a consent-seeking attempt unwinds, so a
    /// mid-attempt identity swap (settle → fresh mint) cannot strand the retired uid's entry.
    func endAllConsentSeeking() {
        guard !consentSeekingUserIds.isEmpty else { return }
        consentSeekingUserIds.removeAll()
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
    ///
    /// FR-74 (F-30): ending an `under13` answer ARMS the device retry-deterrence marker
    /// (`ageGate.under13CooldownUntil`). That is the whole point of the requirement — an
    /// under-13 answer must not be launderable by signing out and immediately re-answering
    /// 13+, so some protective residue survives the epoch it was given in. The marker only
    /// ever extends (`AgeGateRetryCooldownPolicy.cooldownDeadline`); a later `teenAdult`
    /// clear can neither shorten nor erase it.
    func clearAnswer(now: Date = .now) {
        let endedCategory = category
        defaults.removeObject(forKey: AgeGateStoreKeys.category)
        defaults.removeObject(forKey: AgeGateStoreKeys.answeredAt)
        defaults.removeObject(forKey: AgeGateStoreKeys.pendingChildDeclaration)
        if let deadline = AgeGateRetryCooldownPolicy.cooldownDeadline(
            clearedCategory: endedCategory,
            existingDeadline: under13CooldownUntil,
            now: now
        ) {
            defaults.set(deadline.timeIntervalSince1970, forKey: AgeGateStoreKeys.under13CooldownUntil)
        }
        revision += 1
    }

    /// FR-74(d′): applies `AgeGateOnboardingRestartPolicy` at the onboarding entry point —
    /// an UNBOUND `teenAdult` answer does not survive a return to onboarding start, while an
    /// `under13` answer does.
    ///
    /// Deliberately routed through `clearAnswer(now:)` rather than removing the keys
    /// directly, and both reasons are load-bearing:
    ///
    ///  * `clearAnswer` is the ONE place an epoch answer ends, so the uid-bound state it
    ///    preserves — `pendingDeclarationUserIds` and `declaredChildUserIds` — is preserved
    ///    here by construction rather than by a duplicated guard that could drift.
    ///  * its FR-74 cooldown arm keys on the ENDED category, and the only category that can
    ///    reach it from here is `teenAdult`, which arms nothing
    ///    (`AgeGateRetryCooldownPolicy.cooldownDeadline` returns the existing deadline
    ///    untouched for any non-`under13` clear). That is exactly what (d′) needs: a
    ///    re-asked adult is not silently dropped into a deterrence window they never
    ///    earned, and a live window belonging to a real child is neither shortened nor
    ///    extended by this path.
    ///
    /// - Returns: true when the answer was cleared, i.e. the flow must ask again.
    @discardableResult
    func clearUnboundAnswerAtOnboardingStartIfNeeded(
        hasCompletedOnboarding: Bool,
        hasProvisionedIdentity: Bool,
        now: Date = .now
    ) -> Bool {
        guard AgeGateOnboardingRestartPolicy.clearsUnboundAnswerAtOnboardingStart(
            category: category,
            hasCompletedOnboarding: hasCompletedOnboarding,
            hasProvisionedIdentity: hasProvisionedIdentity,
            hasBoundDeclarationUserIds: hasOutstandingChildDeclaration || hasDeclaredChildHistory
        ) else { return false }
        clearAnswer(now: now)
        return true
    }

    /// FR-74: the deterrence marker lifts under the existing FR-39 correction valve
    /// conditions as well — a manager-authorized correction that retires the device's
    /// whole child lineage has more authority than a retry-deterrence timer, and leaving
    /// the marker armed would keep restricting a device the correction just cleared.
    ///
    /// Called ONLY from the correction path (`ChildDeviceCorrectionPolicy.liftsDeviceMarkers`
    /// ⇒ `liftDeviceChildMarkers`). Nothing else may clear it: a self-service clear would
    /// hand the child exactly the escape the marker exists to close.
    func clearUnder13RetryCooldownAfterCorrection() {
        guard under13CooldownUntil != nil else { return }
        defaults.removeObject(forKey: AgeGateStoreKeys.under13CooldownUntil)
        revision += 1
    }
}

// MARK: - Guest provisioning policy (FR-27 / FR-60 acceptance seam)

/// Pure rules for anonymous-identity creation. The age answer is scoped to an
/// IDENTITY EPOCH: sign-out and account deletion clear it, so a stored answer never
/// carries across identities — and no NEW anonymous uid is ever provisioned without
/// an answer for the current epoch. First launch and post-sign-out guest rebirth are
/// the same case; signed-in / keychain-restored sessions (uid exists) never gate.
///
/// FR-60 (F-18) narrows this further: an **under-13 answer no longer provisions at all**.
/// A child who never seeks family consent gets no Firebase account and no `users/{uid}` —
/// they play entirely locally, on a uid-less `AppUser`. The single provisioning moment for
/// that population is share-code entry, which IS the act of seeking consent, and it must
/// say so explicitly at the call site (`isConsentSeekingRedemption`). Nothing else may.
enum GuestProvisioningPolicy {
    /// Gate on `FirebaseAuthService.signInAnonymously` — the single place fresh
    /// anonymous uids are created.
    ///
    /// - Parameters:
    ///   - category: this identity epoch's answer; `nil` = unanswered (FR-27: never provision).
    ///   - isConsentSeekingRedemption: true ONLY on the share-code redemption sequence
    ///     (FR-60(b)). This is the whole exception — it is a parameter rather than a stored
    ///     flag so that "may a child be provisioned right now?" is answered by the caller's
    ///     identity, not by device state an unrelated code path could have left behind.
    ///   - hasDeclaredChildHistory: `AgeGateStore.hasDeclaredChildHistory` — this device has
    ///     confirmed at least one child registration. Device pass 2026-08-17 (bug 2): the
    ///     epoch ANSWER is not sufficient on its own, because it is clearable. `clearAnswer()`
    ///     (sign-out, hard reset, post-deletion) ends the epoch, `requiresAgeGateForGuestProvisioning`
    ///     then becomes true again, and the next answer — a `teenAdult` tap, or `AppCoordinator`'s
    ///     `--skipOnboarding` auto-answer — passed this gate with no reference whatsoever to the
    ///     child lineage the device is still carrying. That is how a settled, uid-less child
    ///     acquired a BRAND-NEW anonymous uid (and, with it, a fresh `users/{uid}` that every
    ///     wave-3b hold was blind to, because those holds key on the RETIRED uid).
    ///
    ///     The ratchet is the protective direction FR-74(d′)/OD-9(iv) already mandate — "device
    ///     child history overrides in all cases". It is not permanent: a manager CORRECTION
    ///     retires the lineage through `clearDeclaredChildUserId`, and signing in to a real
    ///     account never comes through here at all (FR-60(e)/OD-9(i): sign-in or reinstall are
    ///     the sanctioned exits).
    static func mayCreateAnonymousIdentity(
        category: AgeGateCategory?,
        isConsentSeekingRedemption: Bool = false,
        hasDeclaredChildHistory: Bool = false
    ) -> Bool {
        // Consent-seeking redemption is the one sanctioned mint for a child device, and it
        // is checked first so the ratchet can never close the consent exit it protects.
        if isConsentSeekingRedemption {
            return category != nil
        }
        guard !hasDeclaredChildHistory else { return false }
        guard let category else { return false }
        return category != .under13
    }

    /// Whether the current session must pass the age screen before guest provisioning.
    static func requiresAgeGate(hasFirebaseUid: Bool, isResolved: Bool) -> Bool {
        !hasFirebaseUid && !isResolved
    }
}

// MARK: - FR-74 (F-30): age-gate retry deterrence

/// **An under-13 answer cannot be laundered through sign-out.**
///
/// §16's "answer-shopping" row closed re-answering on the SAME identity (`recordAnswer`
/// refuses to overwrite `under13` with `teenAdult`), and FR-39's device ratchet closed the
/// anonymous rebirth. What both left open — R-11, amended into this FR — is sign-out
/// followed by a fresh *registration*: a registered sign-in is exempt from the ratchet by
/// design, so a truthful under-13 answer left no residue against an immediate retry.
///
/// The residue is one device-local deadline. Ending an `under13` answer arms it
/// (`AgeGateStore.clearAnswer`); while it is armed:
///
///  * **(a) re-answering under-13 → the normal child flow, always allowed.** Nothing here
///    can ever refuse a child; the protective answer is never the one being deterred.
///  * **(b) answering 13+ → the account still provisions, but the SESSION is held** at the
///    `.ratchetedAnonymous` equivalent (no ads, no analytics, no location, no purchases,
///    no RevenueCat) until the deadline passes, then normal on the next resolution.
///
/// Fail-closed for the child-retry case, and it only ever DELAYS a genuine adult on a
/// shared device — they play immediately, restricted, and are unrestricted after OD-5's
/// window. Device-local, never synced.
enum AgeGateRetryCooldownPolicy {
    /// OD-5 (owner, defaults acceptable): 24 hours.
    nonisolated static let defaultDuration: TimeInterval = 24 * 60 * 60

    /// The marker to persist when an epoch answer ends.
    ///
    /// Two rules, both load-bearing:
    ///  * only an `under13` answer arms anything — ending a `teenAdult` answer has no
    ///    protective residue to leave;
    ///  * the deadline only ever EXTENDS. A later `teenAdult` clear (sign-out from the very
    ///    session the hold is restricting) must not be able to shorten or erase a live
    ///    window, or the hold would be escapable by signing out twice.
    nonisolated static func cooldownDeadline(
        clearedCategory: AgeGateCategory?,
        existingDeadline: Date?,
        now: Date,
        duration: TimeInterval = defaultDuration
    ) -> Date? {
        guard clearedCategory == .under13 else { return existingDeadline }
        let armed = now.addingTimeInterval(duration)
        guard let existingDeadline else { return armed }
        return max(existingDeadline, armed)
    }

    /// Strictly time-bounded: an elapsed deadline is inactive without anything having to
    /// run to retire it, so a device that was offline (or never relaunched) through the
    /// window is not held a moment longer than the window.
    nonisolated static func isCooldownActive(until: Date?, now: Date) -> Bool {
        guard let until else { return false }
        return until > now
    }

    /// FR-74(b), stated exactly: the hold attaches to a 13+ ANSWER given inside the
    /// window, not to the device and not to an identity.
    ///
    /// An `under13` answer is NOT held here — it is `.childDirected` by its own evidence,
    /// which is strictly stronger; and an UNANSWERED epoch is not held here either, because
    /// it has nothing to be trusted about yet and FR-19/FR-39 already keep it `.unresolved`
    /// or `.ratchetedAnonymous`. Sign-IN is untouched (D-17: sign-in never asks), so a
    /// session that gave no answer is not restricted by this rule.
    nonisolated static func holdsSessionPosture(
        category: AgeGateCategory?,
        isCooldownActive: Bool
    ) -> Bool {
        isCooldownActive && category == .teenAdult
    }
}

// MARK: - FR-74(a′) / OD-9: account provenance as age evidence

/// OD-9 (owner, 2026-08-14): *"Guest accounts ARE in the cloud, only children accounts are
/// local… No one should ever be in an unresolved state other than kids' accounts."*
///
/// Under FR-60 the act of PROVISIONING is itself the age evidence: an under-13 epoch cannot
/// mint a cloud account except through the declare-first redemption path, which sets
/// `isChildAccount = true` BEFORE the first profile write (and holds that write when the
/// declaration fails, so no flagless child document can exist). Therefore a **flagless
/// `users/{uid}` document structurally means "born from a 13+ answer."**
///
/// So a fresh, ingest-gated server read of an EXISTING self document satisfies the epoch
/// half of the age test in place of the device answer — which is what un-bricks the
/// keychain-restored guest whose UserDefaults a reinstall wiped (ads, purchases, location).
///
/// STRICT SCOPE, per OD-8's resolution note: read-provenance answers the epoch/location
/// trust question ONLY. The FR-39 device-marker CORRECTION path still demands a literal
/// server-written `false` (`ChildDeviceCorrectionPolicy`), because there an absent key
/// genuinely is absence of evidence and trusting it would erase a real child's protections
/// irreversibly. Do not widen this into that path.
///
/// Accepted residuals (OD-9(v)): an offline reinstalled guest holds until first
/// connectivity, and a tampered client minting a flagless document is equivalent to lying
/// at the neutral screen.
enum AgeGateAccountProvenancePolicy {
    /// - Parameter freshChildAccountResolution: `UserRepository.isChildAccount(for:)` for
    ///   the CURRENT auth uid. Its tri-state is exactly the signal this needs: an entry
    ///   exists only when THIS session read `users/{uid}` from the server, ungated by cache
    ///   or pending writes (`ChildFlagIngestPolicy`), AND the document existed — every
    ///   ingest site skips an absent document. `nil` therefore means "no such evidence",
    ///   never "adult".
    /// - Parameter isRetryCooldownActive: FR-74 wins over OD-9 where they meet. A device
    ///   inside the deterrence window has child history by definition, and OD-9(iv) is
    ///   explicit that device child history overrides in all cases — so provenance may not
    ///   resolve an epoch there.
    nonisolated static func resolvesEpoch(
        freshChildAccountResolution: Bool?,
        isRetryCooldownActive: Bool = false
    ) -> Bool {
        guard !isRetryCooldownActive else { return false }
        return freshChildAccountResolution != nil
    }
}

// MARK: - FR-74(b′) / OD-9(ii): the immediate rebirth ask

/// *"A session must never reach gameplay UI age-unasked."*
///
/// D-17's incident was not that the age question was asked — it was that it was asked
/// 10–20 seconds late, after gameplay UI had already rendered. OD-9(ii) settles it: a
/// post-sign-out rebirth (a NEW guest with genuinely no information) is asked **at session
/// start, before the first interactive frame**, and that boundary is the sanctioned one.
///
/// D-17's no-mid-session-prompt rule is untouched and is why the caller must evaluate this
/// ONCE per process, at the splash→root transition. A hard sign-out that happens mid-session
/// must NOT raise this screen under the player's hands; that rebirth stays a restricted
/// local guest (option B) until the next launch, which is where this fires.
enum AgeGateSessionStartPolicy {
    /// - Parameters:
    ///   - hasCompletedOnboarding: before onboarding completes, the in-flow asks own the
    ///     question (quick-start's play tap, legacy onboarding's `.ageVerification`,
    ///     sign-up's in-form ask). This gate exists only for sessions that would otherwise
    ///     go straight to gameplay.
    ///   - hasProvisionedIdentity / hasLiveAuthSession: OD-9's own discriminator between its
    ///     two halves. A session that HOLDS an identity is (i) — the keychain-restored guest
    ///     — and resolves through `AgeGateAccountProvenancePolicy` on its first server read,
    ///     or holds until connectivity (OD-9(v)); asking it would contradict that and would
    ///     also drop an under-13 answer onto a restored identity (`RestoredIdentityAgeAnswerPolicy`,
    ///     SRS §3.1.1 items 6/8). Only a session with NO uid and NO Auth session is (ii)'s
    ///     "genuinely no information" rebirth.
    ///   - isRegisteredIdentity: defence in depth. FR-27/D-17 forbid the age answer touching
    ///     a registered account at all; a soft sign-out leaves credentials on the row.
    ///   - hasDeviceChildHistory: OD-9(iv) — device child history overrides in all cases.
    ///     Those devices route through FR-74's cooldown, **never a clean re-ask**.
    nonisolated static func requiresImmediateAsk(
        hasCompletedOnboarding: Bool,
        isAgeAnswered: Bool,
        hasProvisionedIdentity: Bool,
        hasLiveAuthSession: Bool,
        isRegisteredIdentity: Bool,
        hasDeviceChildHistory: Bool
    ) -> Bool {
        guard hasCompletedOnboarding else { return false }
        guard !isAgeAnswered else { return false }
        guard !hasProvisionedIdentity, !hasLiveAuthSession else { return false }
        guard !isRegisteredIdentity else { return false }
        return !hasDeviceChildHistory
    }
}

// MARK: - FR-74(d′): an UNBOUND answer does not survive a return to onboarding start

/// **An abandoned onboarding's age answer is not a lasting answer — unless it is the
/// protective one.**
///
/// Owner-found in device testing 2026-08-15. FR-27 binds an age answer to the identity that
/// gave it, and `clearAnswer()` ends the answer when that identity's epoch ends (sign-out,
/// account deletion). An **abandoned onboarding never provisions an identity at all**, so
/// no epoch ever ends, `clearAnswer()` never fires, the answer floats indefinitely, and
/// `OnboardingCoordinator.stepAfterDisclaimer(isAgeGateResolved:)` skips `.ageVerification`
/// on the next run. The hazard is D-17 incident 2's class exactly: an adult answers,
/// abandons before account creation, hands the device to a child, who resumes onboarding
/// and is silently treated as an adult.
///
/// **The asymmetry is load-bearing.** A `teenAdult` answer is cleared and re-asked; an
/// `under13` answer PERSISTS. Clearing the protective answer would hand a child an
/// answer-shopping escape — restart, answer 1990, be an adult — which is precisely what
/// FR-74's cooldown exists to prevent. It mirrors `recordAnswer`'s standing refusal to
/// overwrite `under13` with `teenAdult`, and FR-19's asymmetric cache trust.
///
/// **Nothing uid-bound is ever cleared here.** `pendingDeclarationUserIds` and
/// `declaredChildUserIds` are promises this device made about SPECIFIC accounts (v2.1
/// FR-27/G29) and outrank any restart; they are only ever READ, as evidence that the answer
/// is bound and therefore out of scope.
enum AgeGateOnboardingRestartPolicy {
    /// - Parameters:
    ///   - category: this device's stored answer. `under13` and "unanswered" are both
    ///     no-ops — the first because it is the protective answer FR-74 refuses to help a
    ///     child shop away (this is also why FR-60's local-first under-13 player, who has
    ///     no account by design and never will, is never in scope), the second because
    ///     there is nothing to clear.
    ///   - hasCompletedOnboarding: `AppCoordinator.hasSeenOnboarding`. The trigger is the
    ///     onboarding ENTRY POINT rendering for a user who has not finished onboarding. A
    ///     user who completed onboarding and is merely replaying a screen is NOT in scope —
    ///     they have an answer bound to a real session, and re-asking them would be the
    ///     mid-session prompt D-17 forbids.
    ///   - hasProvisionedIdentity: `AppUser.firebaseUID != nil`. An identity exists, so the
    ///     answer is bound to an epoch that `clearAnswer()` ends on its own terms; this rule
    ///     has nothing to add and must not pre-empt it.
    ///   - hasBoundDeclarationUserIds: the answer named at least one uid
    ///     (`pendingDeclarationUserIds` ∪ `declaredChildUserIds`). Out of scope for the same
    ///     reason, and protective in the same direction as OD-9(iv) — a device carrying
    ///     child history routes through FR-74's cooldown, never a clean re-ask.
    nonisolated static func clearsUnboundAnswerAtOnboardingStart(
        category: AgeGateCategory?,
        hasCompletedOnboarding: Bool,
        hasProvisionedIdentity: Bool,
        hasBoundDeclarationUserIds: Bool
    ) -> Bool {
        guard category == .teenAdult else { return false }
        guard !hasCompletedOnboarding else { return false }
        guard !hasProvisionedIdentity, !hasBoundDeclarationUserIds else { return false }
        return true
    }
}

// MARK: - Under-13 answer on a RESTORED identity (FR-60(a) completion, FR-74(d′) spirit)

/// FR-60(a) stops an under-13 answer from CREATING an anonymous identity. It says nothing
/// about an identity that already exists — and the iOS Keychain survives app deletion, so a
/// reinstall hands the next session a restored anonymous uid before the age screen is ever
/// shown.
///
/// The result is a chimera, because the two halves of the system key off different things:
///
///  * the flow-scoped half (location restriction, `hasPendingChildDeclaration`) reads the
///    ANSWER, so it correctly treats the session as a child;
///  * the identity-bound half (`ChildRestrictedModeService.childSessionState`, the FR-28
///    banner, `UserDocumentWritePolicy`) reads whether the uid is BOUND to that answer — and
///    a restored uid never passed through `bindPendingDeclaration`, so it reads `.notChild`.
///
/// So the child loses the FR-28 banner (their only route to share-code entry), sees adult
/// "Sign up to access" gates, and — worst — every `users/{uid}` writer is unheld, which
/// creates a FLAGLESS document for a child: a zero-server-footprint population acquiring
/// exactly the footprint FR-60 exists to prevent.
///
/// The resolution follows FR-74(d′)'s asymmetry — a protective answer wins over a stale
/// artefact of a previous epoch. The restored identity is dropped LOCALLY ONLY (it may hold
/// another person's data; deleting it server-side is never this device's call), and the
/// session continues as the clean, unprovisioned local-first child FR-60 specifies.
enum RestoredIdentityAgeAnswerPolicy {
    /// - Parameters:
    ///   - category: the answer just recorded for this epoch.
    ///   - isAnonymousSession: a registered session is out of scope — it has credentials, its
    ///     owner can sign back in, and FR-27 forbids the age answer touching it at all.
    ///   - isBoundToCurrentAnswer: the uid passed through `bindPendingDeclaration` for THIS
    ///     epoch (pending or already declared). A uid this flow provisioned is the normal
    ///     case and must never be detached.
    static func requiresLocalDetach(
        category: AgeGateCategory?,
        isAnonymousSession: Bool,
        isBoundToCurrentAnswer: Bool
    ) -> Bool {
        guard category == .under13 else { return false }
        guard isAnonymousSession else { return false }
        return !isBoundToCurrentAnswer
    }
}

// MARK: - Server-deleted identity detection (FR-60(c) zombie guard)

/// FR-60(c) deletes a declined or expired provisional child: the Auth user AND `users/{uid}`
/// both go. The cleanup deliberately preserves the DEVICE's age answer and ratchet so the
/// child re-enters a code later and "re-provisions cleanly" — but the device also keeps the
/// UID, and both `ChildConsentRedemptionPolicy.requiresProvisioning` and
/// `signInAnonymously` short-circuit on `firebaseUID != nil`. So the re-provision never
/// happens: the next redemption calls with the dead uid, the server's declared-child read
/// hits a missing document, and the caller is refused as unregistered.
///
/// Meanwhile the dead uid is still addressable by every `users/{uid}` merge writer, which
/// resurrects the document — flagless, because rules forbid `isChildAccount` on create.
///
/// Both halves are the same defect: a deleted identity that the device never let go of.
enum DetachedIdentityDetectionPolicy {
    /// What a self-read of `users/{uid}` established about the identity.
    enum SelfDocumentStatus {
        /// Read succeeded and the document exists.
        case present
        /// Read succeeded and the document is CONFIRMED absent.
        case confirmedAbsent
        /// The read failed (offline, transport, App Check). Never actionable — a network
        /// blip must not cost a live account its session.
        case unknown
        /// §3.1.1 item 7 (2026-08-28): the AUTH SERVER itself answered that this user no
        /// longer exists (a forced token refresh failed with a definitive death code).
        /// Stronger than `confirmedAbsent` — a missing doc needs the delivered-declaration
        /// corroboration to prove deletion, but the Auth server's own verdict needs none.
        /// This is what ends the limbo a lapsed JWT otherwise leaves: every doc read fails
        /// as `.unknown` forever while the local store keeps rendering a dead identity.
        case deadIdentity
    }

    /// True when a session must be dropped because the account behind it is gone.
    ///
    /// Scoped to ANONYMOUS sessions whose declaration this device already DELIVERED. That
    /// scope is what makes "absent" provable rather than merely unobserved: a delivered
    /// declaration is a server write, so the document existed; its absence now can only mean
    /// deletion. A brand-new uid mid-provisioning has no delivered declaration yet, so the
    /// rule cannot misfire on it and sign out an account seconds after minting it.
    static func requiresDetach(
        isAnonymousSession: Bool,
        documentStatus: SelfDocumentStatus,
        wasDeclaredByThisDevice: Bool
    ) -> Bool {
        guard isAnonymousSession else { return false }
        // The Auth server's own death verdict is definitive without corroboration — the
        // declared-gate below exists to make doc-ABSENCE provable, and this is stronger.
        if documentStatus == .deadIdentity { return true }
        guard wasDeclaredByThisDevice else { return false }
        return documentStatus == .confirmedAbsent
    }

    /// §3.1.1 item 7 (2026-08-28, wedged-simulator forensics): the teardown is a STATE
    /// the device converges to, not a one-shot event. The original detach can run before
    /// `modelContext` exists (observed: F-18 at launch with every row mutation a silent
    /// `try?` no-op), and the one-way ratchet then blocks a natural retry — so a row can
    /// carry a retired firebaseUID, an activeFamilyId, and local family rows FOREVER
    /// unless something re-checks. True whenever the uid is ratcheted and any residue
    /// remains; the caller re-runs the full teardown, which is idempotent.
    static func requiresResidueTeardown(
        isDetachedUid: Bool,
        rowFirebaseUidPresent: Bool,
        rowActiveFamilyIdPresent: Bool,
        hasLocalFamilyRows: Bool
    ) -> Bool {
        guard isDetachedUid else { return false }
        return rowFirebaseUidPresent || rowActiveFamilyIdPresent || hasLocalFamilyRows
    }

    /// §3.1.1 item 7 (2026-08-28): a DETACHED uid still resolves LOCAL rows — that is
    /// exactly why the teardown leaves it on `AppUser.id` — but it must NEVER key a
    /// cloud channel again: its listeners can only bounce off rules, and its writes can
    /// only resurrect state the server deleted. This is the single tiebreak between the
    /// two uses of `firebaseUID ?? id`, so a launch that re-derives the retired uid
    /// binds nothing.
    static func cloudChannelUserId(
        _ resolvedUserId: String?,
        isDetached: (String) -> Bool
    ) -> String? {
        guard let resolvedUserId, !resolvedUserId.isEmpty else { return nil }
        return isDetached(resolvedUserId) ? nil : resolvedUserId
    }

    /// Whether this session is even worth a server round-trip — the pre-network half of
    /// the decision, so "when do we look?" is testable separately from "what did we see?".
    ///
    /// Device pass 2026-08-16 (bug 1). Wave 1 only ever LOOKED at three moments: the
    /// auth-state bootstrap, a share-code redemption, and Firebase's own force-sign-out.
    /// A captain's remove-and-delete happens while the child's app is in the foreground and
    /// produces none of them — the cached ID token stays valid for the rest of its hour, so
    /// the client keeps reading and writing as an account that no longer exists. Worse, the
    /// window is self-sealing: the first self-doc write in it RECREATES `users/{uid}`, and
    /// the next launch's bootstrap then reads `.present` and never detaches. The detection
    /// therefore has to run on its own schedule (foreground, session restore) rather than
    /// only on identity edges.
    ///
    /// - Parameters:
    ///   - hasFirebaseUid: a uid-less local-first child has nothing to verify.
    ///   - isAlreadyDetached: the ratchet is one-way; a retired uid never needs re-checking.
    static func requiresVerification(
        hasFirebaseUid: Bool,
        isAnonymousSession: Bool,
        wasDeclaredByThisDevice: Bool,
        isAlreadyDetached: Bool,
        isOnline: Bool
    ) -> Bool {
        guard hasFirebaseUid, isAnonymousSession, wasDeclaredByThisDevice else { return false }
        guard !isAlreadyDetached, isOnline else { return false }
        return true
    }

    /// Device pass 2026-08-17 (bug 1): the state NEITHER wave-1 nor wave-3b could see — a
    /// local player still naming a uid while Firebase Auth holds no session at all.
    ///
    /// Both existing detectors are blind to it by construction.
    /// `verifyAnonymousChildIdentityIfNeeded` opens with `guard let firebaseUser = auth.currentUser`,
    /// and `releaseVanishedAnonymousIdentityIfNeeded` needs `lastObservedAnonymousUid`, which is
    /// only ever set by a listener callback that fired WITH a user *in this process*. Kill the
    /// app after a force-sign-out (or lose the race where the listener reaches the teardown
    /// before the bootstrap has published `currentUser`) and neither arms: the uid is never
    /// added to the detached set, so every wave-3b write hold stays inert, and
    /// `ChildConsentRedemptionPolicy.requiresProvisioning` reads `hasFirebaseUid: true` and
    /// skips the mint — which is how the consent exit answered "You are not signed in. Sign in
    /// and try again." to a child who has no account to sign in to.
    ///
    /// No network is involved and none is possible: without a session the `.server` self-read
    /// that `requiresDetach` depends on is refused by rules, so it can only ever return
    /// `.unknown`. The local facts are sufficient and unambiguous — an anonymous identity has
    /// no credentials, so a session that is gone is gone forever.
    ///
    /// - Parameters:
    ///   - isRegisteredIdentity: a registered account CAN sign back in; its uid stays.
    ///   - wasDeclaredByThisDevice: same scoping as `requiresDetach`. Restricts the rule to the
    ///     child lineage this device knows about, so an adult guest's session is never settled
    ///     out from under them by this path.
    static func requiresLocalOnlyDetach(
        hasLocalFirebaseUid: Bool,
        hasLiveAuthSession: Bool,
        isRegisteredIdentity: Bool,
        wasDeclaredByThisDevice: Bool
    ) -> Bool {
        guard hasLocalFirebaseUid, !hasLiveAuthSession else { return false }
        guard !isRegisteredIdentity, wasDeclaredByThisDevice else { return false }
        return true
    }
}

// MARK: - Why an identity was retired (FR-60(a)/(c) settle)

/// `detachAnonymousIdentityLocally` serves two populations that need DIFFERENT settles, and
/// the difference was previously carried by a `StaticString` used only for a DEBUG print.
///
///  * The child whose own account was deleted server-side keeps their local profile: the
///    username and avatar are theirs, the trips are theirs, and only the dead uid goes.
///  * The RESTORED identity that this epoch's under-13 answer does not own is somebody
///    else's account (or a previous epoch's). Wave 1 dropped the session but left the
///    profile it had already hydrated from that account's `users/{uid}` — which is why a
///    reinstall came back as "LittleTimmy" on a device whose age answer had been wiped: the
///    launch bootstrap reads the Keychain-restored uid's document long before the age screen
///    is shown, and the detach that follows never undid the inheritance.
enum IdentityDetachReason: String {
    /// FR-60(a): an under-13 answer landed on an identity it does not own.
    case restoredIdentityUnder13Answer
    /// FR-60(c): a confirmed-absent `users/{uid}` — declined, or remove-and-delete.
    case serverDeletedIdentity
    /// Firebase force-signed-out an anonymous session that no longer exists.
    case vanishedAnonymousSession
    /// A uid already on the one-way ratchet was offered to the session again.
    case alreadyDetachedIdentity
    /// A local player naming a uid with no Auth session left (`requiresLocalOnlyDetach`).
    case sessionLostBeforeRedemption
    /// §3.1.1 item 7 (2026-08-28): a PRIOR detach ran before `modelContext` existed, so
    /// its row mutations silently no-oped while the one-way ratchet stuck — leaving a row
    /// that still carries the retired identity. This re-run converges the device to the
    /// detached state the ratchet already recorded.
    case residualStateAfterDetach

    /// True when the local player must NOT keep the retired account's identity fields.
    /// Only the restored-identity case: there the account belongs to a different answer,
    /// so carrying its username/avatar forward is the same mistake as carrying its uid.
    var discardsInheritedProfile: Bool {
        self == .restoredIdentityUnder13Answer
    }
}

// MARK: - Unconsented-child cloud footprint (FR-60(b)/(d) acceptance seam)

/// FR-60's promise is not "a child's uid is deleted afterwards" — it is that an unconsented
/// child leaves **no server footprint at all**, and FR-60(d) is explicit that the profile
/// write is what "follows" consent, not what precedes it.
///
/// The pre-FR-88 holds could not express that. They key on a UID SET — pending-declaration
/// and detached — so they cover a uid that owes a declaration and a uid that is dead, and
/// nothing in between. The population in between is the one that keeps reappearing in device
/// testing: a child who provisioned at share-code entry (FR-60(b) sanctions the mint) whose
/// redemption then went nowhere — a wrong code, a throttle, a decline that spared the
/// account. They hold a live anonymous uid, no consent, and no family deciding about them,
/// and every ordinary profile writer treats them as an ordinary account. Changing an avatar
/// publishes a child's name and avatar to a server that has no consent to hold either.
///
/// FR-88 is what finally makes the rule expressible: `users/{uid}.pendingFamilyRequest` is
/// server truth for "a family is deciding about me", so the sanctioned window has an
/// observable end as well as a beginning.
///
/// The window, stated once: **a child's cloud profile is writable exactly while consent is
/// being sought or has been granted.**
enum UnconsentedChildCloudWritePolicy {
    /// - Parameters:
    ///   - isUnconsentedChild: `ChildRestrictedModeService.isRestrictedUnconsentedChild`. A
    ///     consented child is a full member (FR-85) and writes freely; an adult is untouched.
    ///   - isFamilyApprovalPending: the FR-88 reconciled value. Server truth wins; the
    ///     device's optimistic flag stands only while the server has not answered, which is
    ///     the same fail-toward-open direction the banner uses — an offline child mid-consent
    ///     must not have their profile write silently dropped.
    ///   - isSeekingConsentNow: this child is PURSUING ADMISSION right now — the whole
    ///     share-code attempt, from the moment the code is submitted until the redemption
    ///     resolves. Their profile write is part of the sanctioned window (FR-83/FR-86 need
    ///     the name and avatar to distinguish two pending children), and it necessarily runs
    ///     before any pending row exists.
    ///
    ///     Device pass 2026-08-17 (wave 8). This parameter was `isConsentSeekingProvisioning`
    ///     and it meant "the uid is inside FR-60(b)'s mint sequence". That is a statement about
    ///     PROVISIONING, and provisioning is the one thing a sticky post-revocation child does
    ///     NOT do — they already hold a uid, so the mint is skipped and the window never
    ///     opened for the population FR-26 names as needing re-admission most. The window is
    ///     about intent, not about identity creation: see `AgeGateStore.beginConsentSeeking`,
    ///     which now owns it for the whole attempt rather than for one method's body.
    static func isWriteHeld(
        isUnconsentedChild: Bool,
        isFamilyApprovalPending: Bool,
        isSeekingConsentNow: Bool
    ) -> Bool {
        guard isUnconsentedChild else { return false }
        return !isFamilyApprovalPending && !isSeekingConsentNow
    }

    /// FR-19's asymmetric trust applied to the WRITE side (SRS §3.1.1 item 5, owner device
    /// find 2026-08-26): an ANONYMOUS session whose server child flag is UNRESOLVED this
    /// process may not write launch bookkeeping (login timestamps).
    ///
    /// `UserRepository.isChildAccount(for:)`'s own contract says "nil is NEVER treated as
    /// 'not child' for gating" — and the launch write was doing exactly that. A reinstall
    /// wipes every device-local child marker (age answer, ratchet, `ChildSignalCache`)
    /// while the Keychain still restores the child's uid, so the first hold answer of the
    /// process was blind and the login-timestamp merge landed on an unconsented child's
    /// `users/{uid}`. Resolve first, write after: on the ordinary online launch the
    /// hydrate ingests the flag BEFORE the tracking write runs, so an adult guest loses
    /// nothing — only a session nobody has classified yet is held, and only until the
    /// server answers.
    ///
    /// Registered (non-anonymous) sessions are exempt: they authenticated with
    /// credentials, and child registered accounts are governed by their own holds.
    static func isUnresolvedAnonymousLaunchWriteHeld(
        isAnonymousSession: Bool,
        resolvedIsChildAccount: Bool?
    ) -> Bool {
        isAnonymousSession && resolvedIsChildAccount == nil
    }
}

// MARK: - Consent-seeking redemption sequence (FR-60(b) acceptance seam)

/// The ordering FR-60(b) mandates when an under-13 local player enters a family share code.
/// Extracted as pure rules so the sequence is pinned by test without Firebase, in the same
/// spirit as `ChildRegistrationOrderingTests`' transcription of the FR-27 sequence.
///
/// Why the order is load-bearing, step by step:
///  1. `mintAnonymousIdentity` — nothing before this exists server-side. This is the first
///     and only moment an under-13 player acquires a backend identity.
///  2. `bindDeclaration` — FR-27's bind-before-publish discipline. The uid is bound
///     SYNCHRONOUSLY, before `currentUser` publishes it, because the instant it is
///     observable SwiftUI can run a `users/{uid}` writer; binding after the declaration's
///     `await` leaves that window unguarded by construction. Violating this is what
///     produced the "created an account, set to child, but am seeing ads" incident.
///  3. `declareChildRegistration` — the server sets `isChildAccount = true` BEFORE any
///     profile write. Under FR-60 it is also what makes step 4 possible at all: the server
///     carve-out (`assertRegisteredAccountOrDeclaredChild`) admits an anonymous caller only
///     on that flag.
///  4. `redeemShareCode` — last. Redeeming with an undeclared uid would present an
///     anonymous, unflagged account to the family, and the captain's approval would then
///     admit a child as an adult.
enum ChildConsentRedemptionPolicy {
    enum Step: Int, CaseIterable, Comparable {
        case mintAnonymousIdentity
        case bindDeclaration
        case declareChildRegistration
        case redeemShareCode

        static func < (lhs: Step, rhs: Step) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// FR-60(b) order, in one place, so a test can assert it rather than a comment.
    static let orderedSteps: [Step] = Step.allCases

    /// True when share-code entry must provision first: an under-13 epoch that has no uid
    /// yet. A child who already holds a uid (declined once and re-entering, or sticky
    /// post-revocation) skips straight to redemption.
    static func requiresProvisioning(hasFirebaseUid: Bool, category: AgeGateCategory?) -> Bool {
        !hasFirebaseUid && category == .under13
    }

    /// FR-60(c) zombie guard, run BEFORE `requiresProvisioning` decides to skip.
    ///
    /// "A child who already holds a uid skips straight to redemption" is only sound while
    /// that uid still exists. After a decline or a remove-and-delete it does not, and the
    /// skip is what strands the child: the callable's declared-child read hits a deleted
    /// document and refuses them as unregistered, on every code they try, forever. The
    /// existing uid therefore has to be verified against the server before it is trusted;
    /// `DetachedIdentityDetectionPolicy` owns the verdict.
    static func requiresIdentityVerification(hasFirebaseUid: Bool, category: AgeGateCategory?) -> Bool {
        hasFirebaseUid && category == .under13
    }

    /// The gate in front of step 4. A uid whose declaration never reached the server is
    /// exactly the "flagless account" failure shape FR-27 exists to prevent, so redemption
    /// is refused and retried rather than proceeding — the uid stays bound and its profile
    /// write stays held (`UserDocumentWritePolicy`), so nothing leaks in the meantime.
    static func mayRedeem(hasFirebaseUid: Bool, isDeclarationOutstanding: Bool) -> Bool {
        hasFirebaseUid && !isDeclarationOutstanding
    }

    /// SRS §3.1.1 item 3 (owner ruling 2026-08-26): only an ACCEPT pursues admission, so
    /// only an accept may run inside the consent-seeking window. §312.5(c)(1) covers
    /// pre-consent identity collection solely for the purpose of obtaining consent — a
    /// child REFUSING an invite is doing the opposite, so a decline must never provision,
    /// publish a profile, or open the window. Wave 8 briefly wrapped both paths; this
    /// policy is what keeps that from coming back unnoticed.
    static func inviteResponseSeeksConsent(accept: Bool) -> Bool { accept }

// MARK: - What the consent exit does with the session in front of it

    /// FR-26/FR-28f (device pass 2026-08-17, wave 8). Re-admission is one of the two exits a
    /// sticky post-revocation child MUST always have, and the exit had a dead end in it.
    ///
    /// `requiresProvisioning` answers ONE question — "must a uid be minted?" — and the caller
    /// treated a `false` as "then there is nothing to do but redeem". That is wrong for the
    /// state this whole family of bugs keeps producing: **a uid on the local row with no Auth
    /// session behind it.** `hasFirebaseUid` is true, so the mint is skipped; the session is
    /// dead, so the exit refuses with `child_gate.join.setup_incomplete`; and the refusal is
    /// worded as retryable while the state that produced it is terminal. Every subsequent code
    /// takes the identical path. That is a locked-out child, which FR-26 forbids.
    ///
    /// Making the decision a total function over the three facts that matter is the fix: there
    /// is no input for which the answer is "refuse", because at this exit there is always
    /// something the device can do.
    enum Resolution: Equatable {
        /// Not a child session and no under-13 answer — an adult redeeming a code. The exit's
        /// ordinary gates own them; this method has nothing to add.
        case passThrough
        /// A live session on an existing uid. The sticky post-revocation child's normal path:
        /// publish the profile inside the window (FR-83/FR-86) and redeem.
        case redeemWithExistingIdentity
        /// A uid whose Auth session is gone. An anonymous session has no credentials, so it is
        /// unrecoverable — the uid is residue. Settle it locally, then mint.
        case settleThenProvision
        /// FR-60(b)'s ordinary first provisioning: an under-13 player with no uid at all.
        case provision
    }

    /// - Parameters:
    ///   - isChildSession: `ChildRestrictedModeService.isChildAccountSession`. Wider than
    ///     `category == .under13` on purpose — a sticky child's evidence can be server truth
    ///     (`isChildAccount`) on a device whose epoch answer was cleared by a reinstall or a
    ///     hard reset, and that child is exactly the one who must not be stranded.
    static func resolution(
        hasFirebaseUid: Bool,
        hasLiveAuthSession: Bool,
        isChildSession: Bool,
        category: AgeGateCategory?
    ) -> Resolution {
        let isChildFlow = isChildSession || category == .under13
        guard isChildFlow else {
            // An adult with no uid still provisions through the ordinary guest path, not this
            // one; an adult with a uid has nothing to do here either.
            return .passThrough
        }
        guard hasFirebaseUid else { return .provision }
        return hasLiveAuthSession ? .redeemWithExistingIdentity : .settleThenProvision
    }
}

// MARK: - Consent assurance levels (FR-59.2 / v4 FR-108 — Swift mirror)

/// The client half of the leveled-consent framework. MIRRORS `consentRequestsCore.ts`
/// exactly — the level lattice and required level are pinned by a parity test on each
/// side, so the two runtimes cannot drift (progression-catalog discipline).
///
/// Owner design 2026-08-27: awaiting-state UI derives from THIS data, not from
/// hardcoded copy — when a Level 2 method ships, its rows describe their own
/// verification channel by adding a case here, and no view changes.
enum ConsentAssurancePolicy {
    /// Server-owned required level; MVP default 1 (email_plus), per the owner's
    /// 2026-08-27 ruling. The runtime knob rides the FR-104 wave.
    static let requiredLevel = 1

    /// The closed method lattice — raw values match the server's consent records.
    enum Method: String, CaseIterable {
        case emailPlus = "email_plus"
        case cardTransaction = "card_transaction"
        case idVerification = "id_verification"

        var assuranceLevel: Int {
            switch self {
            case .emailPlus: return 1
            case .cardTransaction, .idVerification: return 2
            }
        }
    }

    /// What an awaiting-verification approval row shows, keyed by the method in flight.
    /// MVP has exactly one method, so rows resolve it from `requiredLevel`; when a second
    /// method exists the row will carry the server-stamped method instead.
    struct AwaitingPresentation: Equatable {
        var subtitleKey: String
        var cancelAccessibilityKey: String
        var iconSystemName: String
    }

    static func awaitingPresentation(
        method: Method = .emailPlus
    ) -> AwaitingPresentation {
        switch method {
        case .emailPlus:
            return AwaitingPresentation(
                subtitleKey: "family.approval.awaiting_guardian_subtitle",
                cancelAccessibilityKey: "family.a11y.cancel_guardian_confirmation",
                iconSystemName: "envelope.badge"
            )
        case .cardTransaction, .idVerification:
            // Level 2 ships with its own copy; until then these cases are unreachable
            // (no server path mints them) and fall back to the email presentation so a
            // premature record can never render a blank row.
            return awaitingPresentation(method: .emailPlus)
        }
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
    /// - Parameter detachedIdentityUserIds: FR-60(c) zombie guard. A uid this device
    ///   detached because the account no longer exists server-side is held FOREVER — the
    ///   pending-declaration half releases once a declaration lands, which is precisely why
    ///   it never covered a DELETED declared child (its declaration had already landed).
    static func isProfileWriteHeld(
        userUid: String?,
        pendingDeclarationUserIds: Set<String>,
        detachedIdentityUserIds: Set<String> = []
    ) -> Bool {
        guard let userUid, !userUid.isEmpty else { return false }
        return pendingDeclarationUserIds.contains(userUid)
            || detachedIdentityUserIds.contains(userUid)
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
    /// Held for the uids that still owe a child declaration, and forever for the uids this
    /// device detached because the account behind them was deleted server-side.
    static func isWriteHeld(
        userId: String?,
        pendingDeclarationUserIds: Set<String>,
        detachedIdentityUserIds: Set<String> = []
    ) -> Bool {
        AgeGateProfileWritePolicy.isProfileWriteHeld(
            userUid: userId,
            pendingDeclarationUserIds: pendingDeclarationUserIds,
            detachedIdentityUserIds: detachedIdentityUserIds
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
