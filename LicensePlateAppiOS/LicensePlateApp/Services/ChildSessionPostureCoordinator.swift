//
//  ChildSessionPostureCoordinator.swift
//  LicensePlateApp
//
//  COPPA F-7 (FR-17/18/19/23/32/33/34/39): child session postures for ads, analytics,
//  location, and purchases. ONE apply-postures routine, fed by exactly two triggers:
//
//    1. `FirebaseAuthService.handleAuthStateChange` — every identity transition
//       (cold start, sign-in, sign-out, anonymous rebirth).
//    2. A `.userProfilesMerged` observer — mid-session server-side flag changes for
//       the CURRENT uid, including this session's first fresh resolution (FR-23).
//
//  Order inside the routine: cache + ratchet → TFCD (global ads config) → analytics →
//  location → paywall projection → banner teardown/reload-or-remove notification LAST,
//  so a reloading banner can only ever build a request under the already-stamped config.
//
//  Views and ViewModels never touch SDK config (CLAUDE.md layering): they render the
//  published `currentPosture` projections exposed here.
//

import Foundation
import Combine
import FirebaseAuth

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

    /// FR-33 (amended): child sessions force all three location flags off. Scoped to
    /// the child signal only — adult defaults stay untouched (owner decision D-11).
    var forcesLocationOff: Bool {
        self == .childDirected
    }

    /// FR-34: child sessions suppress paywall/upsell surfaces and purchase entry
    /// points. Family-granted `entitlementTags` benefits still apply.
    var suppressesPurchases: Bool {
        self == .childDirected
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
}

enum ChildSessionPosturePolicy {
    static func posture(for signal: ChildSessionSignal) -> ChildSessionPosture {
        // The child signal always wins, from any source (fail-closed, protective).
        if signal.freshIsChildAccount == true
            || signal.cachedIsChildAccount == true
            || signal.isDeclaredChildIdentity {
            return .childDirected
        }
        // FR-39: the ratchet governs anonymous/signed-out sessions regardless of
        // their own doc; a registered (non-anonymous) sign-in is exempt.
        if signal.isAnonymousOrSignedOut, signal.isDeviceRatcheted {
            return .ratchetedAnonymous
        }
        guard signal.hasCurrentUser else { return .unresolved }
        // Anonymous identities carry no registered credentials; their age truth is
        // this device's gate answer. An unanswered epoch (e.g. keychain-restored
        // guest after reinstall) stays held — child-equivalent (F-6 option B).
        if signal.isAnonymousOrSignedOut, !signal.isAgeResolved {
            return .unresolved
        }
        // FR-19 asymmetric trust: only this session's fresh read confirms not-child.
        return signal.freshIsChildAccount == false ? .confirmedNonChild : .unresolved
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
    }

    /// Injectable seams so the routine (order, idempotency, ratchet writes) is
    /// testable without global SDK state.
    struct Dependencies {
        var currentAuthIdentity: () -> (uid: String, isAnonymous: Bool)?
        var freshIsChildAccount: (String) -> Bool?
        var cachedIsChildAccount: (String) -> Bool?
        var storeCachedIsChildAccount: (String, Bool) -> Void
        var isDeclaredChildIdentity: (String?) -> Bool
        /// FR-33 flow window: an under-13 answer recorded for the CURRENT identity
        /// epoch, valid even before the uid is provisioned/declared and before any
        /// posture trigger has re-run (sign-out clears it with the epoch).
        var isUnder13FlowAnswer: () -> Bool
        var isAgeResolved: () -> Bool
        var isDeviceRatcheted: () -> Bool
        var engageDeviceRatchet: () -> Void
        var applyChildDirectedTreatment: (Bool) -> Void
        var setAdPersonalizationSignalsDisabled: (Bool) -> Void
        var setLocationForcedOff: (Bool) -> Void

        @MainActor static func live() -> Dependencies {
            Dependencies(
                currentAuthIdentity: {
                    guard let user = Auth.auth().currentUser else { return nil }
                    return (user.uid, user.isAnonymous)
                },
                freshIsChildAccount: { UserRepository.shared.isChildAccount(for: $0) },
                cachedIsChildAccount: { ChildSignalCache.shared.cachedIsChildAccount(for: $0) },
                storeCachedIsChildAccount: { ChildSignalCache.shared.setCachedIsChildAccount($1, for: $0) },
                isDeclaredChildIdentity: { uid in
                    let store = AgeGateStore.shared
                    if let uid, !uid.isEmpty {
                        return store.pendingDeclarationUserId == uid || store.isDeclaredChildUserId(uid)
                    }
                    // Pre-uid provisional guest: an under-13 answer for the current
                    // flow classifies the session before its uid exists.
                    return store.hasPendingChildDeclaration || store.category == .under13
                },
                isUnder13FlowAnswer: { AgeGateStore.shared.category == .under13 },
                isAgeResolved: { AgeGateStore.shared.isResolved },
                isDeviceRatcheted: { ChildSignalCache.shared.isDeviceRatcheted },
                engageDeviceRatchet: { ChildSignalCache.shared.engageDeviceRatchet() },
                applyChildDirectedTreatment: { AdMobService.shared.applyChildDirectedTreatment($0) },
                setAdPersonalizationSignalsDisabled: {
                    AnalyticsService.shared.setAdPersonalizationSignalsDisabledForChildSession($0)
                },
                setLocationForcedOff: { LocationSettingsService.shared.setChildSessionForcedOff($0) }
            )
        }
    }

    /// Fail-closed initial value: nothing is ad-eligible until a trigger resolves it.
    @Published private(set) var currentPosture: ChildSessionPosture = .unresolved

    // MARK: View-facing projections (views render these; no rule logic in views)

    var isAdDisplayEligible: Bool { currentPosture.isAdDisplayEligible }
    var arePurchasesSuppressed: Bool { currentPosture.suppressesPurchases }
    var isLocationForcedOffForChildSession: Bool { currentPosture.forcesLocationOff }

    /// FR-33 for pre-main flows (onboarding permissions step) and the OS-prompt gate:
    /// child by posture OR by an under-13 answer recorded for the current flow — the
    /// answered-but-not-yet-provisioned window has no gap. Location UI is replaced and
    /// the OS location prompt is never triggered while this is true.
    var isLocationRestrictedForCurrentFlow: Bool {
        currentPosture.forcesLocationOff || deps.isUnder13FlowAnswer()
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
        let fresh: Bool? = uid.flatMap { deps.freshIsChildAccount($0) }
        if let uid, let fresh {
            deps.storeCachedIsChildAccount(uid, fresh)
        }
        let cached: Bool? = uid.flatMap { deps.cachedIsChildAccount($0) }
        let declared = deps.isDeclaredChildIdentity(uid)
        if fresh == true || cached == true || declared {
            deps.engageDeviceRatchet()
        }

        let posture = ChildSessionPosturePolicy.posture(for: ChildSessionSignal(
            hasCurrentUser: uid != nil,
            isAnonymousOrSignedOut: isAnonymousOrSignedOut || uid == nil,
            freshIsChildAccount: fresh,
            cachedIsChildAccount: cached,
            isDeclaredChildIdentity: declared,
            isAgeResolved: deps.isAgeResolved(),
            isDeviceRatcheted: deps.isDeviceRatcheted()
        ))
        let previous = currentPosture

        // 2. Global ads request config (FR-17) — strictly before any banner refresh.
        deps.applyChildDirectedTreatment(posture.childDirectedTreatment)
        // 3. Analytics ad-personalization signals (FR-32).
        deps.setAdPersonalizationSignalsDisabled(posture.disablesAdPersonalizationSignals)
        // 4. Location kill switches (FR-33 amended, all three flags).
        deps.setLocationForcedOff(posture.forcesLocationOff)
        // 5. Publish the paywall/ads projections (FR-34 surfaces consult these).
        currentPosture = posture

        // 6. Banner teardown/reload-or-remove LAST (FR-18): a banner loaded under an
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
