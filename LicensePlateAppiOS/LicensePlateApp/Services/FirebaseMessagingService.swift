//
//  FirebaseMessagingService.swift
//  LicensePlateApp
//
//  Step 18 — FCM token registration path. Firestore writes stay in UserRepository.
//

import Foundation
import UIKit

#if canImport(FirebaseMessaging)
import FirebaseMessaging
#endif

#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

@MainActor
final class FirebaseMessagingService: NSObject {
    static let shared = FirebaseMessagingService()

    private override init() {
        super.init()
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
        #endif
    }

    /// Clears Firestore `fcmToken` for `userId` and deletes the device Messaging token.
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

    /// Account deletion: the server already removed users/{uid} (incl. `fcmToken`), so
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
    func refreshAndPersistTokenIfPossible() async {
        #if canImport(FirebaseMessaging)
        do {
            let token = try await Messaging.messaging().token()
            await persistTokenIfPossible(token)
        } catch {
            CrashReportingService.shared.record(error: error, context: "fcm_token_refresh")
        }
        #endif
    }

    private func persistTokenIfPossible(_ token: String?) async {
        guard let token, !token.isEmpty else { return }
        #if canImport(FirebaseAuth)
        guard let userId = Auth.auth().currentUser?.uid else { return }
        do {
            try await UserRepository.shared.updateFCMToken(userId: userId, token: token)
            AnalyticsService.shared.log(.fcmTokenRegistered)
        } catch {
            CrashReportingService.shared.record(error: error, context: "fcm_token_register")
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
