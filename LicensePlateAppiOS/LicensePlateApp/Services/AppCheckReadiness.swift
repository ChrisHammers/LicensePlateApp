//
//  AppCheckReadiness.swift
//  LicensePlateApp
//

import Foundation
import FirebaseAuth

#if canImport(FirebaseAppCheck)
import FirebaseAppCheck
#endif

enum AppCheckReadiness {
    /// Warm App Check after Firebase configure so the first callable is less likely to race token fetch.
    static func warmUp() {
        Task {
            try? await ensureCallablePrerequisites()
        }
    }

    /// Ensures Firebase Auth and App Check tokens exist before a protected callable.
    static func ensureCallablePrerequisites(forceRefresh: Bool = false) async throws {
        guard let user = Auth.auth().currentUser else {
            throw NSError(
                domain: "AppCheckReadiness",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "User must be authenticated"]
            )
        }

        _ = try await user.getIDToken(forcingRefresh: forceRefresh)

        #if canImport(FirebaseAppCheck)
        do {
            _ = try await AppCheck.appCheck().token(forcingRefresh: forceRefresh)
        } catch {
            throw userFacingAppCheckError(error)
        }
        #endif
    }

    private static func isUnregisteredDebugTokenError(_ error: Error) -> Bool {
        let message = (error as NSError).localizedDescription
        return message.contains("exchangeDebugToken")
            || message.contains("App attestation failed")
    }

    private static func userFacingAppCheckError(_ error: Error) -> Error {
        if isUnregisteredDebugTokenError(error) {
            return NSError(
                domain: "AppCheckReadiness",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: "App Check debug token is not registered for this Firebase project. In the Xcode console, find the line \"Firebase App Check Debug Token: …\", then add it in Firebase Console → App Check → Manage debug tokens, and relaunch the app."]
            )
        }
        return error
    }
}
