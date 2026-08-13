//
//  DeferredSDKStartupService.swift
//  LicensePlateApp
//
//  COPPA F-9 (FR-46): SDK startup deferral, non-ads.
//
//  Three SDK startups must not happen for an AGE-UNRESOLVED session, and must then
//  start with the posture that resolution produced:
//
//    1. FCM registration  — `FirebaseMessagingService.configure` + Messaging auto-init.
//    2. Firebase Analytics COLLECTION — distinct from FR-32's ad-personalization
//       property, which the posture routine applies first (see ordering note below).
//    3. RevenueCat — `configure` + `identify`.
//
//  Firebase core, App Check and Crashlytics are internal-ops and deliberately absent:
//  FR-46 lets them start immediately, and they still do, in `didFinishLaunching`.
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

/// The three FR-46 startups, as one snapshot. Compared against the last applied plan so
/// the service only ever emits deltas (idempotent re-runs are free).
struct DeferredSDKStartupPlan: Equatable {
    var startsMessaging: Bool
    var startsAnalyticsCollection: Bool
    var startsPurchases: Bool

    /// Fail-closed value: what an age-unresolved session gets, and the state the app
    /// installs at launch before anything has resolved.
    static let allDeferred = DeferredSDKStartupPlan(
        startsMessaging: false,
        startsAnalyticsCollection: false,
        startsPurchases: false
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
    static func isAgeResolutionComplete(
        isAgeGateResolved: Bool,
        posture: ChildSessionPosture
    ) -> Bool {
        isAgeGateResolved && posture != .unresolved
    }

    /// The gate is retractable, not a latch: sign-out clears the epoch answer (F-6), so
    /// the rebirth session closes it again until the next answer. That is what makes the
    /// "sign-out → anonymous rebirth" case in FR-46 hold rather than inheriting the
    /// previous account's open gate.
    static func plan(
        isAgeGateResolved: Bool,
        posture: ChildSessionPosture,
        isFirebaseConfigured: Bool,
        hasPurchasesAPIKey: Bool
    ) -> DeferredSDKStartupPlan {
        guard isAgeResolutionComplete(isAgeGateResolved: isAgeGateResolved, posture: posture) else {
            return .allDeferred
        }
        return DeferredSDKStartupPlan(
            // Both are Firebase-side; with no Firebase app configured there is nothing
            // to start (offline-only mode, `initializeFirebase()` returned false).
            startsMessaging: isFirebaseConfigured,
            startsAnalyticsCollection: isFirebaseConfigured,
            // FR-34: a child session never reaches a purchase flow, so RevenueCat is
            // never handed a child identity at all — the strictest reading of "start
            // with the appropriate posture" for an SDK whose only purpose is purchasing.
            // Family-granted `entitlementTags` are unaffected: they come from Firestore
            // (`EntitlementService`), never from RevenueCat.
            startsPurchases: hasPurchasesAPIKey && !posture.suppressesPurchases
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
        var setMessagingAutoInitEnabled: (Bool) -> Void
        var configureMessaging: () -> Void
        var setAnalyticsCollectionEnabled: (Bool) -> Void
        var configurePurchases: () -> Void
        var identifyPurchases: (String?) -> Void

        @MainActor static func live() -> Dependencies {
            Dependencies(
                isAgeGateResolved: { AgeGateStore.shared.isResolved },
                hasPurchasesAPIKey: { RevenueCatEntitlementBridge.shared.hasAPIKey },
                currentAuthUserId: { Auth.auth().currentUser?.uid },
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
                }
            )
        }
    }

    private var deps: Dependencies
    private var isFirebaseConfigured = false
    private var applied: DeferredSDKStartupPlan = .allDeferred
    private var hasConfiguredMessaging = false
    private var hasConfiguredPurchases = false
    private var hasIdentifiedPurchases = false
    private var identifiedPurchaseUserId: String?

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
        guard isFirebaseConfigured else { return }
        deps.setMessagingAutoInitEnabled(false)
        deps.setAnalyticsCollectionEnabled(false)
    }

    /// Called by `ChildSessionPostureCoordinator.applyPostures` for every trigger.
    func apply(posture: ChildSessionPosture) {
        applyPlan(DeferredSDKStartupPolicy.plan(
            isAgeGateResolved: deps.isAgeGateResolved(),
            posture: posture,
            isFirebaseConfigured: isFirebaseConfigured,
            hasPurchasesAPIKey: deps.hasPurchasesAPIKey()
        ))
    }

    private func applyPlan(_ plan: DeferredSDKStartupPlan) {
        // FCM. Auto-init is toggled in both directions; `configure` (APNs registration +
        // delegate + first token fetch) is a one-time bootstrap — re-registering on every
        // later transition would be pointless network work, and sign-out token clearing
        // is already owned by `FirebaseAuthService`.
        if plan.startsMessaging != applied.startsMessaging {
            deps.setMessagingAutoInitEnabled(plan.startsMessaging)
            if plan.startsMessaging, !hasConfiguredMessaging {
                hasConfiguredMessaging = true
                deps.configureMessaging()
            }
        }

        // Analytics collection. FR-32's ad-personalization property was already applied
        // by the posture routine's earlier step, so collection can never be enabled
        // before a child session's posture is in place.
        if plan.startsAnalyticsCollection != applied.startsAnalyticsCollection {
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

        applied = plan
    }
}
