//
//  ChildSessionPostureCoordinator.swift
//  LicensePlateApp
//
//  COPPA F-7 (FR-17/18/19/23/32/33/34/39) + F-31 (FR-75): child session postures for
//  ads, analytics, location, and purchases. ONE apply-postures routine, fed by exactly
//  four triggers:
//
//    1. `FirebaseAuthService.handleAuthStateChange` — every identity transition
//       (cold start, sign-in, sign-out, anonymous rebirth).
//    2. A `.userProfilesMerged` observer — mid-session server-side flag changes for
//       the CURRENT uid, including this session's first fresh resolution (FR-23).
//    3. `AgeGateViewModel.submit()` — the neutral age screen was answered (COPPA F-9,
//       FR-46): age resolution can arrive without the identity or the profile document
//       changing, and the SDK-startup deferral releases on exactly that event.
//    4. `AppDelegate.didFinishLaunching` — the FR-75(b) synchronous launch pass, run
//       from device-local cached signals before any view, view model or tracking
//       service exists. Restrictive steps only (see `Trigger.releasesDeferredSDKStartups`).
//
//  Order inside the routine: cache + ratchet → TFCD (global ads config) → analytics →
//  location → paywall projection → deferred SDK startups (F-9/F-15, ads SDK included) →
//  banner teardown/reload-or-remove notification. The banner refresh stays LAST so a
//  reloading banner can only ever build a request under the already-stamped config, and
//  only after the release step has started the ads SDK (FR-56).
//
//  Views and ViewModels never touch SDK config (CLAUDE.md layering): they render the
//  published `currentPosture` projections exposed here.
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseCore

// MARK: - Posture (pure policy)

/// Effective child-signal classification for the current session. Fail-closed:
/// only `confirmedNonChild` — a fresh server read this session — unlocks ads.
enum ChildSessionPosture: String, Equatable {
    /// Identity-bound child signal: fresh server flag true, cached true, or this
    /// device declared the identity under-13 (F-6 lineage). Owner decision D-6:
    /// ALL child sessions (consented or not) keep every posture below.
    case childDirected
    /// Anonymous/signed-out session on a device that ever hosted a child (FR-39).
    case ratchetedAnonymous
    /// No trustworthy signal yet: age gate unanswered for a guest identity, no auth
    /// user, or a signed-in uid whose `users/{uid}` has not been freshly read this
    /// session (FR-19 asymmetric trust — cached/absent FALSE is never enough).
    case unresolved
    /// Fresh `users/{uid}` read this session confirmed not-child (and, for anonymous
    /// identities, the device age gate is answered). The only ad-eligible posture.
    case confirmedNonChild
}

extension ChildSessionPosture {
    /// FR-17: TFCD is stamped for child and ratcheted-anonymous sessions; resolved
    /// adults get nil. Unresolved sessions stay untagged but are display-held (FR-19),
    /// so no request should be built for them at all.
    var childDirectedTreatment: Bool {
        self == .childDirected || self == .ratchetedAnonymous
    }

    /// FR-19 (amended, D-6): only fresh-confirmed non-child sessions see ads.
    var isAdDisplayEligible: Bool {
        self == .confirmedNonChild
    }

    /// FR-32: child-signal sessions disable Firebase Analytics ad-personalization
    /// signals (belt-and-braces over the app-wide plist OFF floor, F-3).
    var disablesAdPersonalizationSignals: Bool {
        childDirectedTreatment
    }

    /// FR-33 (amended) + FR-75(c): every posture EXCEPT a fresh-confirmed adult forces
    /// all three location capabilities off. Same asymmetric trust as ads (FR-19) and
    /// purchases (FR-57): a session that has not proven it is an adult is not handed a
    /// GPS trail. `.unresolved` and `.ratchetedAnonymous` were the one fail-open
    /// asymmetry left in this engine; they are not any more.
    ///
    /// This is the POSTURE half of the read side. It never mutates the user's stored
    /// preferences; see `rewritesStoredLocationFlagsOff` for that half.
    ///
    /// It is no longer the whole answer: owner decision OD-8 lets `.unresolved` earn its
    /// way out with a trusted adult cache, so the value `EffectiveSettingsResolver`
    /// (FR-75a) and the FR-33 OS-prompt gate actually see comes from
    /// `ChildLocationTrustPolicy`, which starts here and can only ever RELAX this one
    /// posture. Nothing else consults that policy — ads, purchases, analytics and TFCD
    /// keep strict asymmetric trust.
    var forcesLocationOff: Bool {
        self != .confirmedNonChild
    }

    /// FR-33's PERSISTED half, deliberately narrower than `forcesLocationOff`: only a
    /// durable, identity-bound child signal rewrites the user's STORED location flags
    /// to false.
    ///
    /// The rewrite has no inverse — once `LocationSettingsService` writes `false` over
    /// a stored `true`, the original preference is gone. `.unresolved` and
    /// `.ratchetedAnonymous` are TRANSIENT session states (an adult who launches
    /// offline is `.unresolved` for the whole session, because FR-19 accepts only this
    /// session's fresh server read), so letting them rewrite would silently destroy an
    /// adult's saved preferences — exactly what owner decision D-11 forbids. Those
    /// postures are enforced structurally instead, which needs no stored state and
    /// reverses cleanly the moment the session resolves adult.
    var rewritesStoredLocationFlagsOff: Bool {
        self == .childDirected
    }

    /// FR-34 + FR-57: every posture except a fresh-confirmed adult suppresses
    /// paywall/upsell surfaces, purchase entry points, and the RevenueCat startup that
    /// backs them. Same asymmetric trust as ads: a session that has not proven it is an
    /// adult is not handed to a commerce SDK, and `.ratchetedAnonymous` — a device that
    /// has hosted a child — is exactly the case FR-57 overturns. Family-granted
    /// `entitlementTags` benefits still apply.
    var suppressesPurchases: Bool {
        self != .confirmedNonChild
    }

    /// FR-79 (F-35): every posture except a fresh-confirmed adult loses the app's
    /// unmanaged contact and commercial exits — Help & About's support `mailto:`/
    /// rate-app rows, the review-prompt request, and the trip-share action. Same
    /// asymmetric trust as ads and purchases (FR-19): a session that has not proven it
    /// is an adult does not get an unsupervised door out of the app. Explicitly
    /// `nonisolated`: this is a pure value-type predicate with no MainActor state, and
    /// the module's default actor isolation is MainActor.
    nonisolated var suppressesUnmanagedExits: Bool {
        self != .confirmedNonChild
    }

    /// FR-71 (F-27): every posture except a fresh-confirmed adult stops the device from
    /// transmitting a search query at all — `UserRepository.searchUsers` returns empty
    /// locally before any network call, mirroring `userSearch.ts`'s server-side child
    /// short-circuit. Same asymmetric trust as ads, purchases and unmanaged exits
    /// (FR-19): a session that has not proven it is an adult does not get to enumerate
    /// other users. Explicitly `nonisolated`: pure value-type predicate, no MainActor
    /// state.
    nonisolated var suppressesUserSearch: Bool {
        self != .confirmedNonChild
    }
}

/// Inputs snapshot for posture derivation. Pure and synchronous so the matrix is
/// exhaustively testable.
struct ChildSessionSignal: Equatable {
    /// An auth uid exists (anonymous or registered).
    var hasCurrentUser: Bool
    /// No auth user, or the auth user is anonymous (FR-39 ratchet scope).
    var isAnonymousOrSignedOut: Bool
    /// This session's fresh `users/{uid}.isChildAccount` (nil = not read yet).
    var freshIsChildAccount: Bool?
    /// Device cache of the last resolved value for this uid (nil = never resolved).
    var cachedIsChildAccount: Bool?
    /// F-6 identity lineage: this uid was declared under-13 by this device (or the
    /// current flow's answer is pending/bound to it).
    var isDeclaredChildIdentity: Bool
    /// F-6 age gate answered for this identity epoch.
    var isAgeResolved: Bool
    var isDeviceRatcheted: Bool
    /// FR-74(b) (F-30): a 13+ answer given inside this device's under-13 retry-deterrence
    /// window. `AgeGateStore.isUnder13RetryCooldownHeld`.
    var isUnder13RetryCooldownHeld: Bool = false
    /// FR-74(a′) / OD-9: this session made a fresh, ingest-gated SERVER read of an
    /// EXISTING `users/{uid}` for the current identity, which under FR-60 is itself age
    /// evidence. `AgeGateAccountProvenancePolicy.resolvesEpoch`.
    var hasAccountProvenance: Bool = false
}

enum ChildSessionPosturePolicy {
    static func posture(for signal: ChildSessionSignal) -> ChildSessionPosture {
        // The child signal always wins, from any source (fail-closed, protective).
        // FR-74(a) rides on this unchanged: re-answering under-13 during a cooldown is
        // the normal child flow, always allowed — a protective answer is never deterred.
        if signal.freshIsChildAccount == true
            || signal.cachedIsChildAccount == true
            || signal.isDeclaredChildIdentity {
            return .childDirected
        }
        // FR-74(b) (F-30), and it must sit ABOVE the FR-39 branch below rather than
        // inside it. R-11 amended FR-39 precisely because its ratchet exempts registered
        // sign-ins, which left "sign out → fresh registration" as a clean escape from a
        // truthful under-13 answer. The hold attaches to the 13+ ANSWER, so it reaches the
        // registered account that answer went on to provision — that IS the amendment.
        // Held at the `.ratchetedAnonymous` equivalent, not `.childDirected`: this session
        // is not evidenced as a child, so it must not rewrite stored location preferences
        // (`rewritesStoredLocationFlagsOff`, D-11) — it is merely not trusted yet.
        if signal.isUnder13RetryCooldownHeld {
            return .ratchetedAnonymous
        }
        // FR-39: the ratchet governs anonymous/signed-out sessions regardless of
        // their own doc; a registered (non-anonymous) sign-in is exempt.
        if signal.isAnonymousOrSignedOut, signal.isDeviceRatcheted {
            return .ratchetedAnonymous
        }
        guard signal.hasCurrentUser else { return .unresolved }
        // Anonymous identities carry no registered credentials; their age truth is
        // this device's gate answer — OR, per FR-74(a′)/OD-9, the provenance of the
        // account they are already running on: a reinstall wipes the epoch answer while
        // the Keychain restores the uid, and holding that guest forever was the
        // "permanent no-ads install" consequence OD-9 supersedes. Provenance can only
        // ever get the session PAST this hold; it never confers `.confirmedNonChild` on
        // its own, because the line below still demands this session's fresh `false`.
        if signal.isAnonymousOrSignedOut, !signal.isAgeResolved, !signal.hasAccountProvenance {
            return .unresolved
        }
        // FR-19 asymmetric trust: only this session's fresh read confirms not-child.
        return signal.freshIsChildAccount == false ? .confirmedNonChild : .unresolved
    }
}

// MARK: - Location trust (FR-75 amendment, owner decision OD-8)

/// OD-8 (owner, 2026-08-14): "no degraded offline-adult session — trust the local flag
/// for location." FR-75(c) made `.unresolved` force location off, which is right for a
/// device with no evidence, but an ESTABLISHED ADULT who launches offline is
/// `.unresolved` for the whole session (`ChildFlagIngestPolicy` correctly refuses cached
/// Firestore snapshots), and lost route tracking, the map dot and save-location for it.
///
/// This policy is the ONE narrowing of FR-19's asymmetric-trust rule, and it applies to
/// the LOCATION capability only. Ads, purchases, analytics and TFCD stamping keep strict
/// asymmetric trust — they read `ChildSessionPosture` directly and never come through
/// here (see `ChildSessionPostureCoordinator`'s projections).
///
/// SAFETY ARGUMENT (why location may be trusted here and ads may not): FR-19's rule was
/// written for the ads path, which has NO backstop — a request built under a stale
/// cached `false` reaches an ad network untagged and nothing downstream can undo it.
/// Location now has a backstop: FR-76 strips a child actor's coordinates SERVER-SIDE at
/// upload, so a stale cached `false` cannot put a child's coordinates anywhere off the
/// device. Route points are local-only regardless — they never leave the device at all.
/// The stale-cache worst case therefore leaks nothing; it shows a map dot on the device
/// the child is already holding.
///
/// The trust is deliberately hard to earn: it needs POSITIVE local evidence of adulthood
/// for the current uid, and ZERO child evidence anywhere on the device.
///
/// KNOWN GAP (reported to the owner; needs a ruling — do not silently "fix" it here):
/// OD-8 assumes an established adult's device holds a SERVER-EXPLICIT `false`. Today it
/// does not. `users/{uid}.isChildAccount` is server-owned (the client asserts it never
/// writes it); the server writes `true` on declaration/consent and writes `false` from
/// exactly ONE path — a manager CORRECTION of an already-flagged child
/// (`familyChildStatusFlows.ts`; `evaluateApprovalChildDeclaration` returns `none` for a
/// non-sticky target, so approving an adult writes nothing). An ordinary adult document
/// therefore carries NO key, `parseChildAccountResolution` reports
/// `isServerExplicit == false`, and this branch does not fire for them. Two ways to close
/// it, both owner calls: have the server write `isChildAccount: false` explicitly when it
/// creates a user document, or relax condition (3) below from "the document carried the
/// key" to "the value came from a fresh, ingest-gated server read". Until then the branch
/// is correct-but-narrow, and the amendment's user-visible half is the neutral notice copy.
enum ChildLocationTrustPolicy {

    /// Everything the location answer depends on, snapshotted so the matrix is pure and
    /// exhaustively testable.
    struct Inputs: Equatable {
        var posture: ChildSessionPosture
        /// Device cache of the last server-resolved value for the CURRENT uid.
        var cachedIsChildAccount: Bool?
        /// FR-75 amendment: whether that cached value came from a document that
        /// EXPLICITLY carried `isChildAccount`. An absent key resolves `false` under §4
        /// but is the absence of evidence, so it earns no trust here.
        var isCachedValueServerExplicit: Bool
        var isDeviceRatcheted: Bool
        var hasDeclaredChildHistory: Bool
        var hasOutstandingChildDeclaration: Bool
        var hasAnyCachedChildTrue: Bool
        var isUnder13FlowAnswer: Bool
        /// OD-14 (owner, 2026-09-07): the device's own ADULT evidence — a 13+ answer for this
        /// identity epoch — may carry LOCATION while the session is still `.unresolved`.
        var isAdultDeviceAnswer: Bool
        /// OD-14: a CREDENTIALED session (password/OAuth provider attached) is adult evidence
        /// too — sign-in never asks the age question (D-17), so the credential is the adult
        /// claim there. Anonymous and custom-token sessions are not.
        var isCredentialedSession: Bool

        init(
            posture: ChildSessionPosture,
            cachedIsChildAccount: Bool? = nil,
            isCachedValueServerExplicit: Bool = false,
            isDeviceRatcheted: Bool = false,
            hasDeclaredChildHistory: Bool = false,
            hasOutstandingChildDeclaration: Bool = false,
            hasAnyCachedChildTrue: Bool = false,
            isUnder13FlowAnswer: Bool = false,
            isAdultDeviceAnswer: Bool = false,
            isCredentialedSession: Bool = false
        ) {
            self.posture = posture
            self.cachedIsChildAccount = cachedIsChildAccount
            self.isCachedValueServerExplicit = isCachedValueServerExplicit
            self.isDeviceRatcheted = isDeviceRatcheted
            self.hasDeclaredChildHistory = hasDeclaredChildHistory
            self.hasOutstandingChildDeclaration = hasOutstandingChildDeclaration
            self.hasAnyCachedChildTrue = hasAnyCachedChildTrue
            self.isUnder13FlowAnswer = isUnder13FlowAnswer
            self.isAdultDeviceAnswer = isAdultDeviceAnswer
            self.isCredentialedSession = isCredentialedSession
        }
    }

    /// Any child evidence this device holds, from any source and any epoch. Used both to
    /// veto the trusted-adult branch and to choose the notice copy.
    static func hasDeviceChildHistory(_ inputs: Inputs) -> Bool {
        inputs.isDeviceRatcheted
            || inputs.hasAnyCachedChildTrue
            || inputs.hasDeclaredChildHistory
            // An undelivered declaration is a promise this device made about a specific
            // account (`AgeGateStore.clearAnswer`); it outranks any cached adult value,
            // exactly as it blocks the F-8 device lift.
            || inputs.hasOutstandingChildDeclaration
    }

    /// The OD-8 branch. All five owner conditions, each load-bearing:
    ///  1. `.unresolved` only — the other postures are decided by their own evidence.
    ///  2. a cached `false` for the CURRENT uid (positive local evidence, not silence).
    ///  3. that cached value is SERVER-EXPLICIT (the document carried the key).
    ///  4. zero child history on the device (ratchet / declared / pending / cached-true).
    ///  5. the current epoch's age answer is not under-13.
    /// Absent cache, reinstall, and post-sign-out guest rebirth all fail (2)/(3) and stay
    /// restricted — the accepted residual OD-8 names explicitly.
    static func trustsCachedAdultForLocation(_ inputs: Inputs) -> Bool {
        guard inputs.posture == .unresolved else { return false }
        guard inputs.cachedIsChildAccount == false, inputs.isCachedValueServerExplicit else { return false }
        guard !hasDeviceChildHistory(inputs) else { return false }
        return !inputs.isUnder13FlowAnswer
    }

    /// The OD-14 branch (owner, 2026-09-07: "I do not want location turned off for adults
    /// when we are offline — that's a very important part of the game"). While the posture
    /// is still `.unresolved` — no fresh server read THIS session, which is every offline
    /// launch — the device's own adult evidence carries LOCATION, and only location:
    ///  1. `.unresolved` only — every other posture is decided by its own evidence.
    ///  2. adult evidence on the device: a 13+ answer for this epoch, or a registered
    ///     (credentialed) session — sign-in never asks the age question, so the credential
    ///     IS the adult claim there.
    ///  3. nothing cached says child (a cached `true` is child evidence, and wins).
    ///  4. zero child history on the device (ratchet / declared / pending / cached-true).
    ///  5. the current epoch's age answer is not under-13.
    /// Residual, accepted with the ruling: a child who lied at the neutral age screen keeps
    /// location offline exactly as they would online (an age screen is not verification),
    /// and an account a captain flags as child while the device is offline regains child
    /// treatment at the next server read — D-11's rewrite then persists it. Ads, purchases,
    /// analytics and TFCD keep strict asymmetric trust; this relaxes location alone.
    static func trustsDeviceAdultForLocation(_ inputs: Inputs) -> Bool {
        guard inputs.posture == .unresolved else { return false }
        guard inputs.isAdultDeviceAnswer || inputs.isCredentialedSession else { return false }
        guard inputs.cachedIsChildAccount != true else { return false }
        guard !hasDeviceChildHistory(inputs) else { return false }
        return !inputs.isUnder13FlowAnswer
    }

    /// Posture-scoped answer: FR-75(c)'s hold, with the OD-8 and OD-14 branches subtracted.
    static func forcesLocationOff(_ inputs: Inputs) -> Bool {
        guard inputs.posture.forcesLocationOff else { return false }
        return !trustsCachedAdultForLocation(inputs) && !trustsDeviceAdultForLocation(inputs)
    }

    /// Flow-scoped answer (FR-33): the same hold, widened by an under-13 answer recorded
    /// for the current identity epoch — the window before a uid even exists.
    static func isLocationRestricted(_ inputs: Inputs) -> Bool {
        forcesLocationOff(inputs) || inputs.isUnder13FlowAnswer
    }

    /// Which copy the location notice should use (FR-75 amendment / OD-8). A restriction
    /// backed by child evidence keeps the child-account wording; a restriction held for
    /// want of a fresh read — the reinstall/offline residual — is not about a child and
    /// must not tell an adult it is.
    static func isRestrictionChildEvidenced(_ inputs: Inputs) -> Bool {
        inputs.posture == .childDirected
            || inputs.posture == .ratchetedAnonymous
            || inputs.isUnder13FlowAnswer
            || hasDeviceChildHistory(inputs)
    }
}

// MARK: - Manager correction (COPPA F-8 handoff, owner-approved)

/// A parent correction (`setFamilyMemberChildStatus(false)` / approval with explicit
/// `isChild: false`) clears the SERVER flag. Nothing on the child's own device knew
/// that before F-8, so a corrected account kept applying child postures — including the
/// device ratchet — until reinstall.
///
/// The rule: a FRESH `users/{uid}` read of `false` for a uid this device declared under
/// 13 IS the authority, because only a family manager can produce that value. A
/// REVOCATION is not a correction — there the flag stays `true`, so this never fires and
/// every protection persists (sticky flag, §4).
enum ChildDeviceCorrectionPolicy {
    /// Identity-scoped half: does this resolution retire THIS uid's child lineage?
    ///
    /// Three independent conditions, each load-bearing:
    /// 1. `freshIsChildAccount == false` — a cached or unresolved value never counts
    ///    (FR-19 asymmetric trust runs in the protective direction too).
    /// 2. `isFreshValueServerExplicit` — the document must have literally carried
    ///    `isChildAccount: false`. An ABSENT key also reads as `false` under §4, but it
    ///    is the absence of evidence, not a manager's decision. Any writer that creates
    ///    a flagless `users/{uid}` (see `UserDocumentWritePolicy`) would otherwise
    ///    manufacture a "correction" that permanently erases a real child's lineage —
    ///    strictly worse than the original bug, because nothing can ever re-flag it.
    ///    `familyChildStatusFlows.ts` always writes the key explicitly, so requiring it
    ///    never blocks a genuine correction.
    /// 3. `wasDeclaredChildIdentity` — a CONFIRMED declaration (the uid is in
    ///    `declaredChildUserIds`). A uid that merely OWES a declaration is not
    ///    correctable: the server was never told it is a child, so a `false` there is
    ///    the missing declaration itself.
    ///
    /// A REVOCATION is not a correction — there the flag stays `true`, so this never
    /// fires and every protection persists (sticky flag, §4).
    static func isCorrection(
        freshIsChildAccount: Bool?,
        isFreshValueServerExplicit: Bool,
        wasDeclaredChildIdentity: Bool
    ) -> Bool {
        freshIsChildAccount == false && isFreshValueServerExplicit && wasDeclaredChildIdentity
    }

    /// Device-scoped half, evaluated AFTER the corrected uid has been removed: the
    /// ratchet and the stored under-13 answer may lift only when no other cached-true or
    /// declared child identity remains on this device, AND no uid still owes a
    /// declaration (an undelivered promise about a specific account outranks a
    /// correction for a different one).
    static func liftsDeviceMarkers(
        hasAnyCachedChildTrue: Bool,
        hasDeclaredChildHistory: Bool,
        hasOutstandingChildDeclaration: Bool
    ) -> Bool {
        !hasAnyCachedChildTrue && !hasDeclaredChildHistory && !hasOutstandingChildDeclaration
    }
}

// MARK: - Banner refresh notification (FR-18)

extension Notification.Name {
    /// Posted by `ChildSessionPostureCoordinator` AFTER the global ads config is
    /// re-stamped, whenever the effective posture changes. Live banners tear down and
    /// either reload (adult transitions) or are removed (child/hold transitions).
    static let adIdentityDidChange = Notification.Name("ChildSessionPostureCoordinator.adIdentityDidChange")
}

enum AdIdentityChangeKeys {
    /// Bool: whether the new posture may display ads (reload) or not (remove).
    static let isAdDisplayEligible = "isAdDisplayEligible"
}

// MARK: - Coordinator

@MainActor
final class ChildSessionPostureCoordinator: ObservableObject {
    static let shared = ChildSessionPostureCoordinator()

    enum Trigger: String {
        case identityTransition = "identity_transition"
        case profileMerge = "profile_merge"
        /// COPPA F-9 (FR-46): the neutral age screen was just answered. Age resolution is
        /// the other way a session's posture can become knowable without the identity or
        /// the profile document changing, and FR-46's deferral releases on exactly that
        /// event — so it feeds the SAME routine rather than a parallel one.
        case ageResolution = "age_resolution"
        /// COPPA F-31 (FR-75b): the synchronous launch pass, from `didFinishLaunching`.
        /// The three triggers above are all asynchronous — the earliest of them runs
        /// behind `RootView`'s remote-config fetch and `initializeAuthState`. Until it
        /// lands, a device that ALREADY knows it hosts a child had factory-default
        /// `true` location flags and (after a previous grant) live OS authorization,
        /// which is the window this closes. Reads only what is available synchronously
        /// at launch: `ChildSignalCache`, `AgeGateStore`, and the auth identity Firebase
        /// restored during `configure`.
        case launch = "launch"

        /// FR-75(b) vs FR-46/FR-58. The launch pass runs before any server read can have
        /// happened, so its posture is derived from cached / device-local signals alone.
        /// It applies every RESTRICTIVE step immediately, but does NOT release the
        /// deferred SDK startups: FR-58 installs those holds microseconds earlier and
        /// FR-46 releases them on this session's RESOLUTION, which a cached signal is
        /// not. The identity-transition trigger that follows releases them exactly as
        /// before, so SDK startup timing is unchanged by F-31.
        var releasesDeferredSDKStartups: Bool { self != .launch }
    }

    /// Injectable seams so the routine (order, idempotency, ratchet writes) is
    /// testable without global SDK state.
    struct Dependencies {
        var currentAuthIdentity: () -> (uid: String, isAnonymous: Bool)?
        var freshIsChildAccount: (String) -> Bool?
        /// Whether this session's resolution came from a document that EXPLICITLY
        /// carried `isChildAccount`. Gates the destructive correction path only —
        /// posture derivation deliberately ignores it (an adult doc never has the key).
        var isFreshChildFlagExplicit: (String) -> Bool
        var cachedIsChildAccount: (String) -> Bool?
        /// `(uid, isChild, isServerExplicit)`. Provenance travels WITH the value —
        /// same discipline as `UserRepository.ingestChildAccountResolution` — so no
        /// call site can persist a cached `false` without saying whether the server
        /// actually wrote the key (FR-75 amendment / OD-8 depends on that bit).
        var storeCachedIsChildAccount: (String, Bool, Bool) -> Void
        var isDeclaredChildIdentity: (String?) -> Bool
        /// FR-33 flow window: an under-13 answer recorded for the CURRENT identity
        /// epoch, valid even before the uid is provisioned/declared and before any
        /// posture trigger has re-run (sign-out clears it with the epoch).
        var isUnder13FlowAnswer: () -> Bool
        /// OD-14: the current epoch's answer is 13+. Fail-closed default for an unwired
        /// harness — absence of adult evidence keeps location held, never releases it.
        var isAdultDeviceAnswer: () -> Bool = { false }
        /// OD-14: a CREDENTIALED session — a password/OAuth provider is attached. Anonymous
        /// sessions and custom-token sessions (how FR-84 signs a transferred CHILD in) have
        /// no provider and are never adult evidence. Fail-closed default.
        var isCredentialedSession: () -> Bool = { false }
        var isAgeResolved: () -> Bool
        var isDeviceRatcheted: () -> Bool
        var engageDeviceRatchet: () -> Void
        /// F-8 correction seams. `clearChildIdentityLineage` retires ONE uid (declared
        /// history + cached value); the two predicates report what child lineage the
        /// device still holds; `liftDeviceChildMarkers` drops the ratchet and the stored
        /// under-13 answer.
        var clearChildIdentityLineage: (String) -> Void
        var hasAnyCachedChildTrue: () -> Bool
        var hasDeclaredChildHistory: () -> Bool
        /// Correction gate input: this uid's declaration was CONFIRMED delivered.
        /// Deliberately narrower than `isDeclaredChildIdentity`, which also reports
        /// uids that merely owe a declaration — those are never correctable.
        var hasConfirmedChildDeclaration: (String) -> Bool
        /// Any uid on this device still owing a declaration; blocks the device lift.
        var hasOutstandingChildDeclaration: () -> Bool
        var liftDeviceChildMarkers: () -> Void
        var applyChildDirectedTreatment: (Bool) -> Void
        var setAdPersonalizationSignalsDisabled: (Bool) -> Void
        var setLocationForcedOff: (Bool) -> Void
        /// COPPA F-9/F-15 (FR-46/FR-56): releases — or re-holds — the deferred SDK
        /// startups (FCM, RevenueCat, Analytics collection, Google Mobile Ads) for the
        /// posture this routine just derived. Declared last with a no-op default so the
        /// existing constructions stay source-compatible; `live()` wires the real gate.
        var releaseDeferredSDKStartups: (ChildSessionPosture) -> Void = { _ in }
        /// FR-75 amendment (OD-8): whether the DEVICE CACHE's value for a uid came from
        /// a server-explicit `isChildAccount`. Read only by the location projection.
        /// Declared last with a fail-closed default (`false` = never trusted) so
        /// existing constructions stay source-compatible and an unwired harness cannot
        /// accidentally opt into the trusted branch.
        var isCachedChildFlagServerExplicit: (String) -> Bool = { _ in false }
        /// FR-74(b) (F-30): a 13+ answer inside this device's under-13 retry-deterrence
        /// window. Fail-OPEN default (`false` = not held) is correct here and is the only
        /// safe direction for an unwired harness: the default must not manufacture a
        /// restriction no device state supports. Real state comes from `AgeGateStore`.
        var isUnder13RetryCooldownHeld: () -> Bool = { false }
        /// FR-74 (F-30): whether this device's deterrence window is open at all,
        /// independent of the current answer. Read by the OD-9 provenance branch, which
        /// FR-74 outranks (OD-9(iv): device child history overrides in all cases).
        var isUnder13RetryCooldownActive: () -> Bool = { false }

        @MainActor static func live() -> Dependencies {
            Dependencies(
                currentAuthIdentity: {
                    // FR-75(b): the launch pass runs inside `didFinishLaunching`, which
                    // in offline-only mode (no Firebase plist, `initializeFirebase()`
                    // returned false) has no configured app — `Auth.auth()` would trap.
                    // No identity then, and the device-local child signals still apply.
                    guard FirebaseApp.app() != nil, let user = Auth.auth().currentUser else { return nil }
                    return (user.uid, user.isAnonymous)
                },
                freshIsChildAccount: { UserRepository.shared.isChildAccount(for: $0) },
                isFreshChildFlagExplicit: { UserRepository.shared.isChildAccountFlagExplicit(for: $0) },
                cachedIsChildAccount: { ChildSignalCache.shared.cachedIsChildAccount(for: $0) },
                storeCachedIsChildAccount: { uid, isChild, isServerExplicit in
                    ChildSignalCache.shared.setCachedIsChildAccount(
                        isChild,
                        for: uid,
                        isServerExplicit: isServerExplicit
                    )
                },
                isDeclaredChildIdentity: { uid in
                    let store = AgeGateStore.shared
                    if let uid, !uid.isEmpty {
                        return store.isPendingDeclaration(userId: uid) || store.isDeclaredChildUserId(uid)
                    }
                    // Pre-uid provisional guest: an under-13 answer for the current
                    // flow classifies the session before its uid exists.
                    return store.hasPendingChildDeclaration || store.category == .under13
                },
                isUnder13FlowAnswer: { AgeGateStore.shared.category == .under13 },
                isAdultDeviceAnswer: { AgeGateStore.shared.category == .teenAdult },
                isCredentialedSession: {
                    guard let user = Auth.auth().currentUser else { return false }
                    return !user.isAnonymous && !user.providerData.isEmpty
                },
                isAgeResolved: { AgeGateStore.shared.isResolved },
                isDeviceRatcheted: { ChildSignalCache.shared.isDeviceRatcheted },
                engageDeviceRatchet: { ChildSignalCache.shared.engageDeviceRatchet() },
                clearChildIdentityLineage: { uid in
                    AgeGateStore.shared.clearDeclaredChildUserId(uid)
                    ChildSignalCache.shared.clearCachedIsChildAccount(for: uid)
                },
                hasAnyCachedChildTrue: { ChildSignalCache.shared.hasAnyCachedChildTrue },
                hasDeclaredChildHistory: { AgeGateStore.shared.hasDeclaredChildHistory },
                hasConfirmedChildDeclaration: { uid in
                    let store = AgeGateStore.shared
                    return store.isDeclaredChildUserId(uid) && !store.isPendingDeclaration(userId: uid)
                },
                hasOutstandingChildDeclaration: { AgeGateStore.shared.hasOutstandingChildDeclaration },
                liftDeviceChildMarkers: {
                    ChildSignalCache.shared.disengageDeviceRatchet()
                    AgeGateStore.shared.clearUnder13AnswerAfterCorrection()
                    // FR-74: "the marker … lifts under the existing FR-39 correction
                    // valve conditions as well". A manager correction that retires the
                    // device's whole child lineage outranks a retry-deterrence timer;
                    // leaving it armed would keep restricting a corrected device.
                    AgeGateStore.shared.clearUnder13RetryCooldownAfterCorrection()
                },
                applyChildDirectedTreatment: { AdMobService.shared.applyChildDirectedTreatment($0) },
                setAdPersonalizationSignalsDisabled: {
                    AnalyticsService.shared.setAdPersonalizationSignalsDisabledForChildSession($0)
                },
                setLocationForcedOff: { LocationSettingsService.shared.setChildSessionForcedOff($0) },
                releaseDeferredSDKStartups: { DeferredSDKStartupService.shared.apply(posture: $0) },
                isCachedChildFlagServerExplicit: { ChildSignalCache.shared.isCachedValueServerExplicit(for: $0) },
                isUnder13RetryCooldownHeld: { AgeGateStore.shared.isUnder13RetryCooldownHeld() },
                isUnder13RetryCooldownActive: { AgeGateStore.shared.isUnder13RetryCooldownActive() }
            )
        }
    }

    /// Fail-closed initial value: nothing is ad-eligible until a trigger resolves it.
    @Published private(set) var currentPosture: ChildSessionPosture = .unresolved

    // MARK: View-facing projections (views render these; no rule logic in views)

    /// Ads, purchases and analytics read the posture DIRECTLY — strict FR-19 asymmetric
    /// trust, untouched by OD-8. Only the location projections below consult
    /// `ChildLocationTrustPolicy`.
    var isAdDisplayEligible: Bool { currentPosture.isAdDisplayEligible }
    var arePurchasesSuppressed: Bool { currentPosture.suppressesPurchases }
    /// FR-79 (F-35): Help & About's contact/rate-app rows, the review-prompt request,
    /// and the trip-share action all read this one projection.
    var suppressesUnmanagedExits: Bool { currentPosture.suppressesUnmanagedExits }

    /// Posture-scoped location hold (FR-75c), narrowed by OD-8's trusted-adult-cache
    /// branch. Views that replace their location toggles read this.
    var isLocationForcedOffForChildSession: Bool {
        ChildLocationTrustPolicy.forcesLocationOff(locationTrustInputs)
    }

    /// FR-33 for pre-main flows (onboarding permissions step) and the OS-prompt gate:
    /// child by posture OR by an under-13 answer recorded for the current flow — the
    /// answered-but-not-yet-provisioned window has no gap. Location UI is replaced and
    /// the OS location prompt is never triggered while this is true.
    var isLocationRestrictedForCurrentFlow: Bool {
        ChildLocationTrustPolicy.isLocationRestricted(locationTrustInputs)
    }

    /// FR-75 amendment (OD-8): whether a live location restriction has child evidence
    /// behind it. Drives `ChildLocationDisabledNotice`'s copy so the residual held cases
    /// (reinstall / offline first launch, no local evidence either way) stop telling an
    /// adult their account is a child's.
    var isLocationRestrictionChildEvidenced: Bool {
        ChildLocationTrustPolicy.isRestrictionChildEvidenced(locationTrustInputs)
    }

    /// Snapshot of the device-local signals the location answer depends on. Read LIVE
    /// rather than cached at `applyPostures` time — the same way the under-13 flow
    /// answer has always been read — so the projection cannot go stale behind a marker
    /// that moved outside the routine. `applyPostures` republishes unconditionally
    /// (step 5), which is what carries a changed answer to subscribers.
    private var locationTrustInputs: ChildLocationTrustPolicy.Inputs {
        let uid = deps.currentAuthIdentity()?.uid
        return ChildLocationTrustPolicy.Inputs(
            posture: currentPosture,
            cachedIsChildAccount: uid.flatMap { deps.cachedIsChildAccount($0) },
            isCachedValueServerExplicit: uid.map { deps.isCachedChildFlagServerExplicit($0) } ?? false,
            isDeviceRatcheted: deps.isDeviceRatcheted(),
            hasDeclaredChildHistory: deps.hasDeclaredChildHistory(),
            hasOutstandingChildDeclaration: deps.hasOutstandingChildDeclaration(),
            hasAnyCachedChildTrue: deps.hasAnyCachedChildTrue(),
            isUnder13FlowAnswer: deps.isUnder13FlowAnswer(),
            isAdultDeviceAnswer: deps.isAdultDeviceAnswer(),
            isCredentialedSession: deps.isCredentialedSession()
        )
    }

    private var deps: Dependencies
    private var cancellables = Set<AnyCancellable>()

    init(dependencies: Dependencies? = nil) {
        self.deps = dependencies ?? Dependencies.live()
        // Trigger 2 (FR-23): merges of the CURRENT uid's profile re-run the routine —
        // covers mid-session server-side flips and this session's first resolution
        // (the offline-device-comes-online case included).
        NotificationCenter.default.publisher(for: .userProfilesMerged)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                let mergedIds = (notification.userInfo?["userIds"] as? [String]) ?? []
                self?.noteUserProfilesMerged(userIds: mergedIds)
            }
            .store(in: &cancellables)
    }

    /// FR-23 merge trigger body (separated so tests can drive it deterministically).
    /// Only merges that include the CURRENT uid matter; the routine is idempotent.
    func noteUserProfilesMerged(userIds: [String]) {
        guard let uid = deps.currentAuthIdentity()?.uid, userIds.contains(uid) else { return }
        applyPostures(trigger: .profileMerge)
    }

    /// The one apply-postures routine (FR-23). Idempotent: safe to re-run with
    /// unchanged inputs; the banner notification fires only on posture changes.
    func applyPostures(trigger: Trigger) {
        let identity = deps.currentAuthIdentity()
        let uid = identity?.uid
        let isAnonymousOrSignedOut = identity?.isAnonymous ?? true

        // 1. Cache + ratchet BEFORE posture derivation, so a fresh child resolution
        //    both persists for the next cold start and shapes this session now.
        //    The resolution's PROVENANCE is cached with it (FR-75 amendment / OD-8):
        //    only a server-explicit `false` can later stand in for a fresh read, and
        //    only for location.
        let fresh: Bool? = uid.flatMap { deps.freshIsChildAccount($0) }
        if let uid, let fresh {
            deps.storeCachedIsChildAccount(uid, fresh, deps.isFreshChildFlagExplicit(uid))
        }

        // 1b. F-8: a manager CORRECTION (fresh false on a uid this device declared)
        //     retires that identity's child lineage, and — only if no other child
        //     identity remains — the device-level markers too. A revocation leaves the
        //     flag true, so nothing below runs and every protection persists.
        if let uid,
           ChildDeviceCorrectionPolicy.isCorrection(
               freshIsChildAccount: fresh,
               isFreshValueServerExplicit: deps.isFreshChildFlagExplicit(uid),
               wasDeclaredChildIdentity: deps.hasConfirmedChildDeclaration(uid)
           ) {
            deps.clearChildIdentityLineage(uid)
            if ChildDeviceCorrectionPolicy.liftsDeviceMarkers(
                hasAnyCachedChildTrue: deps.hasAnyCachedChildTrue(),
                hasDeclaredChildHistory: deps.hasDeclaredChildHistory(),
                hasOutstandingChildDeclaration: deps.hasOutstandingChildDeclaration()
            ) {
                deps.liftDeviceChildMarkers()
            }
        }

        let cached: Bool? = uid.flatMap { deps.cachedIsChildAccount($0) }
        let declared = deps.isDeclaredChildIdentity(uid)
        if fresh == true || cached == true || declared {
            deps.engageDeviceRatchet()
        }

        // FR-74(a′) / OD-9: `fresh` is non-nil exactly when THIS session resolved
        // `users/{uid}` from a server read that passed `ChildFlagIngestPolicy` AND the
        // document existed — every ingest site skips an absent document. That is the
        // "fresh server-resolved read of an existing users/{uid}" OD-9 names, and it is
        // scoped to the CURRENT auth identity by construction (a detached uid has no auth
        // session, so it never reaches here as `uid`).
        let hasAccountProvenance = AgeGateAccountProvenancePolicy.resolvesEpoch(
            freshChildAccountResolution: fresh,
            isRetryCooldownActive: deps.isUnder13RetryCooldownActive()
        )

        let posture = ChildSessionPosturePolicy.posture(for: ChildSessionSignal(
            hasCurrentUser: uid != nil,
            isAnonymousOrSignedOut: isAnonymousOrSignedOut || uid == nil,
            freshIsChildAccount: fresh,
            cachedIsChildAccount: cached,
            isDeclaredChildIdentity: declared,
            isAgeResolved: deps.isAgeResolved(),
            isDeviceRatcheted: deps.isDeviceRatcheted(),
            isUnder13RetryCooldownHeld: deps.isUnder13RetryCooldownHeld(),
            hasAccountProvenance: hasAccountProvenance
        ))
        let previous = currentPosture

        // 2. Global ads request config (FR-17) — strictly before any banner refresh.
        deps.applyChildDirectedTreatment(posture.childDirectedTreatment)
        // 3. Analytics ad-personalization signals (FR-32).
        deps.setAdPersonalizationSignalsDisabled(posture.disablesAdPersonalizationSignals)
        // 4. Location kill switches (FR-33 amended, all three flags). The PERSISTED
        //    rewrite is scoped to `rewritesStoredLocationFlagsOff` — a durable child
        //    signal — because it destroys the stored value it overwrites. The wider
        //    FR-75(c) hold (`forcesLocationOff`, published in step 5) is what actually
        //    denies the capability to every non-adult posture, structurally, via
        //    `EffectiveSettingsResolver` and the FR-33 prompt gate.
        deps.setLocationForcedOff(posture.rewritesStoredLocationFlagsOff)
        // 5. Publish the paywall/ads projections (FR-34 surfaces consult these).
        //    The assignment is UNCONDITIONAL on purpose: `@Published` republishes on
        //    every set, and since the FR-75 amendment the location projections read
        //    device state (cache + provenance + ratchet + declarations) as well as the
        //    posture, so a run that leaves the posture alone while moving one of those
        //    — a sign-out to a uid with no cached value, say — must still notify
        //    `EffectiveSettingsResolver`. Do not guard this with an equality check.
        currentPosture = posture

        // 6. COPPA F-9/F-15 (FR-46/FR-56): the deferred SDKs (FCM, RevenueCat, Analytics
        //    collection, Google Mobile Ads) start — or stay held — for the posture just
        //    applied. Strictly after step 3, so Analytics COLLECTION can never be enabled
        //    before a child session's ad-personalization posture is in place; strictly
        //    after step 2, so `MobileAds.start()` can only ever run under an
        //    already-stamped TFCD value; and strictly before step 7, so no banner
        //    reloads into an unstarted SDK. The FR-75(b) launch pass skips this step
        //    only (see `Trigger.releasesDeferredSDKStartups`).
        if trigger.releasesDeferredSDKStartups {
            deps.releaseDeferredSDKStartups(posture)
        }

        // 7. Banner teardown/reload-or-remove LAST (FR-18): a banner loaded under an
        //    old config is never left showing, and any reload sees the new config.
        if posture != previous {
            NotificationCenter.default.post(
                name: .adIdentityDidChange,
                object: nil,
                userInfo: [AdIdentityChangeKeys.isAdDisplayEligible: posture.isAdDisplayEligible]
            )
        }
    }
}
