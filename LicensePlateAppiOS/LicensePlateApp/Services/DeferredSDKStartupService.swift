//
//  DeferredSDKStartupService.swift
//  LicensePlateApp
//
//  COPPA F-9 (FR-46) + F-15 (FR-56): SDK startup deferral.
//
//  Four SDK startups must not happen for an AGE-UNRESOLVED session, and must then
//  start with the posture that resolution produced:
//
//    1. FCM registration  — `FirebaseMessagingService.configure` + Messaging auto-init.
//    2. Firebase Analytics COLLECTION — distinct from FR-32's ad-personalization
//       property, which the posture routine applies first (see ordering note below).
//    3. RevenueCat — `configure` + `identify`.
//    4. Google Mobile Ads — `MobileAds.start()` (FR-56). It used to start
//       unconditionally in `didFinishLaunching`, which on a clean install meant an
//       untagged SDK init before the age gate had even been shown.
//
//  Firebase core, App Check and Crashlytics are internal-ops and deliberately absent:
//  FR-46 lets them start immediately, and they still do, in `didFinishLaunching`.
//
//  COPPA F-28 (FR-72(a)) narrows #2 past age resolution: collection starts for a confirmed
//  adult, and for a child only when the child is consented AND F-21's `analytics_internal`
//  scope is granted. That scope is not built yet, so every child session runs with
//  collection off (`isConsentedChildAnalyticsScopeGranted` is the one seam F-21 wires).
//  COPPA F-29 (FR-73) narrows #1: an unconsented child is age-resolved but may hold no
//  push token, so FCM is neither auto-inited nor configured for them — no token is minted.
//
//  This is NOT a second posture mechanism. `ChildSessionPostureCoordinator` remains the
//  one apply-postures routine; it calls `apply(posture:)` here as its last step, so every
//  identity transition, every `.userProfilesMerged` (FR-23) and the age answer itself
//  re-evaluate the gate. Everything here is a pure delta over injectable seams — no
//  Firebase, no RevenueCat, no timing.
//

import Foundation
import FirebaseAuth

// MARK: - Which deferred SDKs a session may start (pure policy)

/// The four deferred startups, as one snapshot. Compared against the last applied plan
/// so the service only ever emits deltas (idempotent re-runs are free).
struct DeferredSDKStartupPlan: Equatable {
    var startsMessaging: Bool
    var startsAnalyticsCollection: Bool
    var startsPurchases: Bool
    var startsAds: Bool

    /// Fail-closed value: what an age-unresolved session gets, and the state the app
    /// installs at launch before anything has resolved.
    static let allDeferred = DeferredSDKStartupPlan(
        startsMessaging: false,
        startsAnalyticsCollection: false,
        startsPurchases: false,
        startsAds: false
    )
}

enum DeferredSDKStartupPolicy {
    /// FR-46's "age-unresolved" test, made explicit. BOTH halves are required:
    ///
    /// - `isAgeGateResolved` — this device's neutral age screen (F-6) has an answer for
    ///   the current identity epoch. This is the literal age signal FR-46 names.
    /// - `posture != .unresolved` — the session's child signal actually resolved. FR-46
    ///   does not merely say "start late", it says the SDKs "start with the appropriate
    ///   posture"; `.unresolved` means no posture has been established yet, so there is
    ///   nothing correct to start under. Matches FR-19's asymmetric trust: a cached or
    ///   absent `false` never counts as a resolution.
    ///
    /// Neither half implies the other. A ratcheted-anonymous session (FR-39) has a
    /// posture but no age answer; a signed-in session can have an age answer while its
    /// `users/{uid}` read is still outstanding.
    /// FR-74(a′) / OD-9 amends the FIRST half only: **account provenance stands in for the
    /// device epoch answer.** A keychain-restored guest's UserDefaults died with the
    /// reinstall while their cloud account did not, and under FR-60 that account's mere
    /// existence is age evidence (`AgeGateAccountProvenancePolicy`). Without this the
    /// restored guest is age-unresolved forever and every deferred SDK stays held — the
    /// "permanent no-ads install" consequence OD-9 explicitly supersedes.
    ///
    /// The SECOND half is untouched: `.unresolved` still blocks, so provenance can never
    /// start an SDK for a session whose child signal has not landed.
    static func isAgeResolutionComplete(
        isAgeGateResolved: Bool,
        hasAccountProvenance: Bool = false,
        posture: ChildSessionPosture
    ) -> Bool {
        (isAgeGateResolved || hasAccountProvenance) && posture != .unresolved
    }

    /// The gate is retractable, not a latch: sign-out clears the epoch answer (F-6), so
    /// the rebirth session closes it again until the next answer. That is what makes the
    /// "sign-out → anonymous rebirth" case in FR-46 hold rather than inheriting the
    /// previous account's open gate.
    static func plan(
        isAgeGateResolved: Bool,
        hasAccountProvenance: Bool = false,
        isUnder13RetryCooldownHeld: Bool = false,
        posture: ChildSessionPosture,
        isFirebaseConfigured: Bool,
        hasPurchasesAPIKey: Bool,
        isUnconsentedChild: Bool = false,
        isConsentedChildAnalyticsScopeGranted: Bool = false
    ) -> DeferredSDKStartupPlan {
        // FR-74(b) (F-30): a 13+ answer inside the under-13 deterrence window is "held at
        // the `.ratchetedAnonymous` equivalent — no ads, no analytics, no location, no
        // purchases, no RevenueCat". The posture alone gets four of the five (ads and
        // purchases via `isAdDisplayEligible`/`suppressesPurchases`, location via
        // `forcesLocationOff`), but not analytics collection on its own; FR-72(a)'s posture
        // term below now keeps `.ratchetedAnonymous` collection off, and deferring
        // everything is what makes "equivalent" literally true rather than nearly true.
        guard !isUnder13RetryCooldownHeld else { return .allDeferred }
        guard isAgeResolutionComplete(
            isAgeGateResolved: isAgeGateResolved,
            hasAccountProvenance: hasAccountProvenance,
            posture: posture
        ) else {
            return .allDeferred
        }
        return DeferredSDKStartupPlan(
            // Both are Firebase-side; with no Firebase app configured there is nothing
            // to start (offline-only mode, `initializeFirebase()` returned false).
            // Messaging is FR-46's half only; the consent half is `PushTokenEligibilityPolicy`,
            // applied by the service before anything is minted (FR-73).
            startsMessaging: isFirebaseConfigured,
            // FR-72(a): a confirmed adult, or a consented child with the
            // `analytics_internal` scope. The scope cannot open it for an unconsented
            // child, and `.ratchetedAnonymous` stays off even with an answer (OD-14b keeps
            // analytics under strict asymmetric trust there).
            startsAnalyticsCollection: isFirebaseConfigured && (
                posture == .confirmedNonChild
                    || (posture == .childDirected
                        && !isUnconsentedChild
                        && isConsentedChildAnalyticsScopeGranted)
            ),
            // FR-34: a child session never reaches a purchase flow, so RevenueCat is
            // never handed a child identity at all — the strictest reading of "start
            // with the appropriate posture" for an SDK whose only purpose is purchasing.
            // Family-granted `entitlementTags` are unaffected: they come from Firestore
            // (`EntitlementService`), never from RevenueCat.
            startsPurchases: hasPurchasesAPIKey && !posture.suppressesPurchases,
            // FR-56: the ads SDK starts for exactly the sessions that may DISPLAY ads —
            // `.confirmedNonChild` and nothing else. Same shape as `startsPurchases`
            // (which FR-57 also reduces to that one posture); expressed through the
            // canonical FR-19 projection so there is one definition of ad-eligibility.
            startsAds: posture.isAdDisplayEligible
        )
    }
}

// MARK: - Service (applies the plan as deltas)

@MainActor
final class DeferredSDKStartupService {
    static let shared = DeferredSDKStartupService()

    /// Injectable seams, matching `ChildSessionPostureCoordinator.Dependencies` in style
    /// so the whole gate is testable without Firebase or RevenueCat.
    struct Dependencies {
        var isAgeGateResolved: () -> Bool
        var hasPurchasesAPIKey: () -> Bool
        var currentAuthUserId: () -> String?
        /// FR-74(a′) / OD-9. Derived through the SAME pure policy the posture routine
        /// uses (`AgeGateAccountProvenancePolicy`), so "what counts as provenance" has
        /// exactly one definition. Fail-closed default for unwired harnesses.
        var hasAccountProvenance: () -> Bool = { false }
        /// FR-74(b): the retry-deterrence hold. Fail-open default (`false` = not held) —
        /// an unwired harness must not manufacture a restriction no device state supports.
        var isUnder13RetryCooldownHeld: () -> Bool = { false }
        /// FR-73: FR-28's consent half of push eligibility (and of FR-72(a)'s child term).
        /// Fail-open default (`false` = not an unconsented child), same rationale as the
        /// cooldown hold; `live()` wires the real projection.
        var isUnconsentedChild: () -> Bool = { false }
        /// FR-73: POSITIVE consent evidence, required before a `.childDirected` session may
        /// mint a push token. `isUnconsentedChild` alone fails open while
        /// `ChildRestrictedModeService` is still unconfigured (RootView wires it only after
        /// the Remote Config fetch, and the auth listener can release the SDKs first): a
        /// Keychain-restored, server-flagged child with no device answer reads `.notChild`
        /// there. Fail-closed default; the post-bootstrap posture re-run releases a
        /// consented child.
        var isConsentedChild: () -> Bool = { false }
        /// FR-72(a) — THE F-21 SEAM. Whether this session's consented child has the
        /// `analytics_internal` consent scope (FR-65) granted. F-21 wires it to
        /// "`ChildRestrictedModeService.childSessionState == .consentedChild` AND the
        /// server-side scope is granted"; until then it is deliberately NOT overridden in
        /// `live()`, so every child session runs with collection off. It is only read when
        /// the posture routine re-runs: if the scope is stored outside `users/{uid}`, F-21
        /// must add its own `applyPostures` trigger.
        var isConsentedChildAnalyticsScopeGranted: () -> Bool = { false }
        var setMessagingAutoInitEnabled: (Bool) -> Void
        var configureMessaging: () -> Void
        var setAnalyticsCollectionEnabled: (Bool) -> Void
        var configurePurchases: () -> Void
        var identifyPurchases: (String?) -> Void
        /// FR-56: `MobileAds.start()`, carrying the posture that released it so the
        /// pre-start TFCD stamp is derived from the same value the routine just applied.
        var startAds: (ChildSessionPosture) -> Void

        @MainActor static func live() -> Dependencies {
            Dependencies(
                isAgeGateResolved: { AgeGateStore.shared.isResolved },
                hasPurchasesAPIKey: { RevenueCatEntitlementBridge.shared.hasAPIKey },
                currentAuthUserId: { Auth.auth().currentUser?.uid },
                hasAccountProvenance: {
                    guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else { return false }
                    return AgeGateAccountProvenancePolicy.resolvesEpoch(
                        freshChildAccountResolution: UserRepository.shared.isChildAccount(for: uid),
                        isRetryCooldownActive: AgeGateStore.shared.isUnder13RetryCooldownActive()
                    )
                },
                isUnder13RetryCooldownHeld: { AgeGateStore.shared.isUnder13RetryCooldownHeld() },
                isUnconsentedChild: { ChildRestrictedModeService.shared.isRestrictedUnconsentedChild },
                isConsentedChild: { ChildRestrictedModeService.shared.childSessionState == .consentedChild },
                setMessagingAutoInitEnabled: {
                    FirebaseMessagingService.shared.setAutoInitEnabled($0)
                },
                configureMessaging: {
                    FirebaseMessagingService.shared.configureForResolvedSession()
                },
                setAnalyticsCollectionEnabled: {
                    AnalyticsService.shared.setAnalyticsCollectionEnabled($0)
                },
                configurePurchases: { RevenueCatEntitlementBridge.shared.configure() },
                identifyPurchases: { userId in
                    Task { await RevenueCatEntitlementBridge.shared.identify(userId: userId) }
                },
                startAds: { AdMobService.shared.startIfNeeded(posture: $0) }
            )
        }
    }

    private var deps: Dependencies
    private var isFirebaseConfigured = false
    private var applied: DeferredSDKStartupPlan = .allDeferred
    private var hasConfiguredMessaging = false
    /// FR-73: the messaging state actually applied, which is `plan.startsMessaging` AND
    /// push eligibility. Tracked apart from the plan so consent arriving under an unchanged
    /// plan still starts messaging, and revocation still stops it. `FirebaseMessagingService`
    /// reads it as the startup half of every mint/persist guard, so its refresh paths inherit
    /// this fail-closed consent evidence too.
    private(set) var isMessagingEnabled = false
    private var hasConfiguredPurchases = false
    private var hasIdentifiedPurchases = false
    private var identifiedPurchaseUserId: String?
    private var hasStartedAds = false

    init(dependencies: Dependencies? = nil) {
        self.deps = dependencies ?? Dependencies.live()
    }

    /// View/diagnostic projection: whether the gate is currently open (test + report aid;
    /// no view reads this today).
    var currentPlan: DeferredSDKStartupPlan { applied }

    /// Called once from `didFinishLaunching`, right after Firebase core comes up.
    ///
    /// The holds are APPLIED, not merely assumed. Both Firebase-side switches persist in
    /// UserDefaults across launches, so a previously resolved session would otherwise
    /// re-open Analytics collection and FCM auto-init during the next cold start's
    /// pre-resolution window — exactly the FR-46 acceptance case.
    func installAtLaunch(isFirebaseConfigured: Bool) {
        self.isFirebaseConfigured = isFirebaseConfigured
        applied = .allDeferred
        isMessagingEnabled = false
        guard isFirebaseConfigured else { return }
        deps.setMessagingAutoInitEnabled(false)
        deps.setAnalyticsCollectionEnabled(false)
    }

    /// Called by `ChildSessionPostureCoordinator.applyPostures` for every trigger.
    func apply(posture: ChildSessionPosture) {
        applyPlan(
            DeferredSDKStartupPolicy.plan(
                isAgeGateResolved: deps.isAgeGateResolved(),
                hasAccountProvenance: deps.hasAccountProvenance(),
                isUnder13RetryCooldownHeld: deps.isUnder13RetryCooldownHeld(),
                posture: posture,
                isFirebaseConfigured: isFirebaseConfigured,
                hasPurchasesAPIKey: deps.hasPurchasesAPIKey(),
                isUnconsentedChild: deps.isUnconsentedChild(),
                isConsentedChildAnalyticsScopeGranted: deps.isConsentedChildAnalyticsScopeGranted()
            ),
            posture: posture
        )
    }

    private func applyPlan(_ plan: DeferredSDKStartupPlan, posture: ChildSessionPosture) {
        // COPPA F-29 (FR-73): `isMessagingEnabled` is one of the two inputs
        // `FirebaseMessagingService`'s eligibility guard reads at the moment a token is
        // handed over, and `configureMessaging()` below triggers exactly such a fetch. It
        // (like the plan) is published BEFORE that call, so the fetch never observes a stale
        // `false` for the very release that triggered it (a self-inflicted suppression, not a
        // leak, but a real one). Deltas are computed against the local `previous` (FCM's
        // against `isMessagingEnabled`), so only changes are emitted.
        let previous = applied
        applied = plan

        // FCM. Auto-init is toggled in both directions; `configure` (APNs registration +
        // delegate + first token fetch) is a one-time bootstrap — re-registering on every
        // later transition would be pointless network work, and sign-out token clearing
        // is already owned by `FirebaseAuthService`.
        // FR-73: gated on push eligibility, not the plan alone. Minting is itself the act of
        // creating the persistent identifier, so an unconsented child gets neither auto-init
        // nor `configure` (no APNs or FCM token) until consent re-runs the routine. A child
        // posture needs positive consent evidence, not merely the absence of unconsented.
        let allowsMessaging = PushTokenEligibilityPolicy.allowsTokenRegistration(
            startsMessaging: plan.startsMessaging,
            isUnconsentedChild: deps.isUnconsentedChild()
        ) && (posture != .childDirected || deps.isConsentedChild())
        if allowsMessaging != isMessagingEnabled {
            isMessagingEnabled = allowsMessaging
            deps.setMessagingAutoInitEnabled(allowsMessaging)
            if allowsMessaging, !hasConfiguredMessaging {
                hasConfiguredMessaging = true
                deps.configureMessaging()
            }
        }

        // Analytics collection. FR-32's ad-personalization property was already applied
        // by the posture routine's earlier step, so collection can never be enabled
        // before a child session's posture is in place.
        if plan.startsAnalyticsCollection != previous.startsAnalyticsCollection {
            deps.setAnalyticsCollectionEnabled(plan.startsAnalyticsCollection)
        }

        // RevenueCat. `Purchases.configure` cannot be undone, so it happens once, on the
        // first transition that is allowed to start it; identity changes afterwards are
        // re-`identify`ed, and closing the gate logs the identity back out.
        if plan.startsPurchases {
            if !hasConfiguredPurchases {
                hasConfiguredPurchases = true
                deps.configurePurchases()
            }
            let userId = deps.currentAuthUserId()
            if !hasIdentifiedPurchases || identifiedPurchaseUserId != userId {
                hasIdentifiedPurchases = true
                identifiedPurchaseUserId = userId
                deps.identifyPurchases(userId)
            }
        } else if hasIdentifiedPurchases, identifiedPurchaseUserId != nil {
            // Adult → child correction, or sign-out into an unresolved rebirth: drop the
            // RevenueCat identity. The SDK stays configured (it cannot be un-configured)
            // but holds no user.
            identifiedPurchaseUserId = nil
            deps.identifyPurchases(nil)
        }

        // Google Mobile Ads (FR-56). One-way, like `Purchases.configure`: the SDK cannot
        // be un-started, so it starts on the first plan that allows it — a posture that
        // is both age-resolved and `.confirmedNonChild`. Losing that posture later needs
        // no counterpart here: FR-19's display hold removes the banners (FR-18) and no
        // request is ever built for an ineligible session.
        if plan.startsAds, !hasStartedAds {
            hasStartedAds = true
            deps.startAds(posture)
        }
    }
}
