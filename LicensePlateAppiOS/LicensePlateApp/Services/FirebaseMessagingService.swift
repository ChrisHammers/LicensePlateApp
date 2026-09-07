//
//  FirebaseMessagingService.swift
//  LicensePlateApp
//
//  Step 18 — FCM token registration path. Firestore writes stay in UserRepository.
//
//  COPPA F-29 (FR-73 / v2.1 FR-53): an FCM token is a persistent identifier and therefore
//  personal information. Every path that can MINT or PERSIST one runs through
//  `PushTokenEligibilityPolicy` below.
//

import Foundation
import UIKit

#if canImport(FirebaseMessaging)
import FirebaseMessaging
#endif

#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

// MARK: - Who may hold a push token (pure policy)

/// FR-73(a) — the single definition of "this session may hold an FCM token".
///
/// FR-46 deferred SDK startup for AGE-UNRESOLVED sessions and nothing else, so
/// `DeferredSDKStartupPlan.startsMessaging` answers only half the question: a declared child
/// is *resolved* (as `.childDirected`), so the plan starts messaging for them. That is right
/// for a CONSENTED child — FR-38 bounds their reachable push surface to family trips — and
/// wrong for an unconsented one, who has no consent covering any collection at all.
///
/// Both halves are required and neither implies the other:
///  - `startsMessaging` — FR-46's age-resolution gate, computed by `DeferredSDKStartupPolicy`.
///  - `!isUnconsentedChild` — FR-28's consent gate, computed by `ChildRestrictedModeService`.
///
/// Under FR-60's local-first model a never-consented child has no uid and therefore no token
/// document is even possible; what this guard actually protects is the transient redemption
/// window (uid provisioned, family not yet joined) and the sticky post-revocation child
/// (`isChildAccount` still true, family gone). `firestore.rules` carries the same test as the
/// server-side backstop, and `writeChildMembershipRevocation` deletes what already exists.
enum PushTokenEligibilityPolicy {
    static func allowsTokenRegistration(
        startsMessaging: Bool,
        isUnconsentedChild: Bool
    ) -> Bool {
        startsMessaging && !isUnconsentedChild
    }
}

@MainActor
final class FirebaseMessagingService: NSObject {
    static let shared = FirebaseMessagingService()

    /// FR-73(a) seam: whether this session may mint/persist a token right now. Injectable so
    /// the guard is testable without Firebase, the startup service, or a signed-in identity.
    /// Fail-closed default (`false`) — an unwired instance registers nothing.
    private var isTokenRegistrationAllowedProvider: () -> Bool = { false }

    private override init() {
        super.init()
        self.isTokenRegistrationAllowedProvider = {
            PushTokenEligibilityPolicy.allowsTokenRegistration(
                startsMessaging: DeferredSDKStartupService.shared.currentPlan.startsMessaging,
                isUnconsentedChild: ChildRestrictedModeService.shared.isRestrictedUnconsentedChild
            )
        }
    }

    /// Test seam (and the shape every other service in this layer uses). Production wiring
    /// happens in `init`; nothing outside tests needs to call this.
    func setTokenRegistrationEligibility(_ provider: @escaping () -> Bool) {
        isTokenRegistrationAllowedProvider = provider
    }

    /// FR-73(a): the one question every mint/persist path asks.
    var isTokenRegistrationAllowed: Bool {
        isTokenRegistrationAllowedProvider()
    }

    /// COPPA F-9 (FR-46): FCM must not register for an age-unresolved session.
    /// `isAutoInitEnabled` PERSISTS in UserDefaults across launches, so the gate sets it
    /// explicitly in both directions rather than turning it off once — otherwise a
    /// previously resolved install would auto-generate a token during the next cold
    /// start's pre-resolution window.
    func setAutoInitEnabled(_ enabled: Bool) {
        #if canImport(FirebaseMessaging)
        Messaging.messaging().isAutoInitEnabled = enabled
        #endif
    }

    /// FR-46 release point, called by `DeferredSDKStartupService` once the session's age
    /// posture is known. For a child session this registers exactly what family-trip
    /// notifications need: the token is the same device token, and *which* pushes a child
    /// can receive is decided server-side (FR-38 restricts a child to family trips), so
    /// there is no separate client-side registration to narrow.
    func configureForResolvedSession() {
        configure(application: .shared)
    }

    func configure(application: UIApplication) {
        application.registerForRemoteNotifications()
        #if canImport(FirebaseMessaging)
        Messaging.messaging().delegate = self
        Messaging.messaging().token { token, error in
            if let error {
                Task { @MainActor in
                    AnalyticsService.shared.log(.notificationDeliveryFailed(error: error.localizedDescription))
                }
                return
            }
            Task { @MainActor in
                await self.persistTokenIfPossible(token)
            }
        }
        #endif
    }

    func didRegisterForRemoteNotifications(deviceToken: Data) {
        #if canImport(FirebaseMessaging)
        Messaging.messaging().apnsToken = deviceToken
        #if DEBUG
        print("[Push] APNs device token set (\(deviceToken.count) bytes)")
        #endif
        #endif
    }

    /// Clears the Firestore push token (`users/{uid}/private/fcm`) and the device Messaging token.
    /// Call while Auth still represents that user, before `auth.signOut()`.
    func clearTokenForSignOut(userId: String) async {
        guard !userId.isEmpty else { return }

        #if canImport(FirebaseAuth)
        // Prefer clearing the Auth uid's doc so security rules allow the write.
        let cloudUserId = Auth.auth().currentUser?.uid ?? userId
        do {
            try await UserRepository.shared.clearFCMToken(userId: cloudUserId)
        } catch {
            CrashReportingService.shared.record(error: error, context: "fcm_token_clear")
        }
        #endif

        #if canImport(FirebaseMessaging)
        do {
            try await Messaging.messaging().deleteToken()
        } catch {
            CrashReportingService.shared.record(error: error, context: "fcm_token_delete_local")
        }
        #endif
    }

    /// Account deletion: the server already removed users/{uid} and its `private/*` docs
    /// (incl. the `fcm` push-token doc), so
    /// only the device Messaging token is dropped — never a Firestore write that could
    /// resurrect the deleted user doc.
    func deleteDeviceTokenAfterAccountDeletion() async {
        #if canImport(FirebaseMessaging)
        do {
            try await Messaging.messaging().deleteToken()
        } catch {
            CrashReportingService.shared.record(error: error, context: "fcm_token_delete_account_deletion")
        }
        #endif
    }

    /// After guest rebirth / anonymous Auth, attach a fresh token to the new uid.
    ///
    /// FR-73(a) — THE BYPASS CLOSURE. This method has three direct callers that never
    /// consulted the FR-46 startup plan at all: `RootView`'s cloud-channel bring-up and
    /// `FirebaseAuthService`'s two rebirth paths (hard sign-out and post-deletion). Each ran
    /// on an identity whose posture had not necessarily resolved, so `Messaging.token()`
    /// minted a token for age-unknown and rebirth sessions and persisted it — the whole
    /// point of the deferral, routed around. Guarding HERE rather than at the three call
    /// sites is deliberate: a fourth caller inherits the gate instead of re-opening the hole.
    ///
    /// The guard is placed BEFORE `Messaging.token()`, not merely before the write: minting
    /// is itself the act of creating the persistent identifier.
    func refreshAndPersistTokenIfPossible() async {
        guard isTokenRegistrationAllowed else {
            #if DEBUG
            print("[Push] FR-73: token refresh suppressed — session may hold no push token")
            #endif
            return
        }
        #if canImport(FirebaseMessaging)
        do {
            let token = try await Messaging.messaging().token()
            await persistTokenIfPossible(token)
        } catch {
            CrashReportingService.shared.record(error: error, context: "fcm_token_refresh")
            #if DEBUG
            print("[Push] FCM token refresh FAILED: \(error.localizedDescription)")
            #endif
        }
        #endif
    }

    /// FR-73(a), second half of the closure: the LAST gate before a token reaches Firestore.
    ///
    /// `refreshAndPersistTokenIfPossible` covers the three explicit bypass call sites, but it
    /// is not the only way a token arrives — `MessagingDelegate.didReceiveRegistrationToken`
    /// fires on every FCM token ROTATION, unprompted, for as long as the SDK is configured,
    /// and `configure(application:)`'s initial `Messaging.token()` completion lands here too.
    /// A session that was eligible when messaging started and is not eligible now (consent
    /// revoked mid-session, a correction, a rebirth) must not have a rotation write for it.
    /// So eligibility is re-asked at the write, not cached from the start.
    private func persistTokenIfPossible(_ token: String?) async {
        guard let token, !token.isEmpty else { return }
        guard isTokenRegistrationAllowed else {
            #if DEBUG
            print("[Push] FR-73: token persist suppressed — session may hold no push token")
            #endif
            return
        }
        #if canImport(FirebaseAuth)
        guard let userId = Auth.auth().currentUser?.uid else { return }
        do {
            try await UserRepository.shared.updateFCMToken(userId: userId, token: token)
            AnalyticsService.shared.log(.fcmTokenRegistered)
            #if DEBUG
            print("[Push] FCM token persisted to private/fcm")
            #endif
        } catch {
            CrashReportingService.shared.record(error: error, context: "fcm_token_register")
            #if DEBUG
            print("[Push] FCM token persist FAILED: \(error.localizedDescription)")
            #endif
        }
        #endif
    }
}

#if canImport(FirebaseMessaging)
extension FirebaseMessagingService: MessagingDelegate {
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        Task { @MainActor in
            await FirebaseMessagingService.shared.persistTokenIfPossible(fcmToken)
        }
    }
}
#endif
