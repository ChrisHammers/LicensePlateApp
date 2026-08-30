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
    /// Warm App Check after Firebase configure so the first callable doesn't race a cold
    /// provider. DETACHED and never awaited — nothing user-facing spends time in here.
    ///
    /// Bug B deep cause (2026-08-30): the old body called `ensureCallablePrerequisites`,
    /// which throws BEFORE touching App Check whenever `Auth.auth().currentUser` is nil —
    /// and on the FIRST process after a fresh install the Keychain session has not
    /// restored yet (or doesn't exist), so App Check never warmed on exactly the process
    /// where every physical-device wedge occurred; the `FamilyCallable` standard-path
    /// fallback then had an empty cache and re-sent the SDK's placeholder (the observed
    /// double-401). App Check has NO dependency on Auth; the coupling was incidental.
    /// This warms the token directly, with bounded retries for the fast-failure modes
    /// (cold DeviceCheck at first launch — the placeholder class). A HANGING attempt
    /// still pins the SDK's memoized promise for the process (GACAppCheck TODO(#42):
    /// retries and forced refreshes join the stuck promise), so retries deliberately
    /// can't help that class — it is unrecoverable per-process by any client means, and
    /// the FamilyCallable limited-use path is unaffected by the pinned promise anyway.
    static func warmUp() {
        Task.detached(priority: .utility) {
            await warmStandardTokenWithRetries()
        }
    }

    /// Delay before each warm-up attempt; the run stops on the first success.
    static let warmupAttemptDelaysSeconds: [Double] = [0, 10, 60]

    /// Test seam: `fetch` replaces the live App Check token request; `attemptDelaysSeconds`
    /// replaces the real backoff.
    static func warmStandardTokenWithRetries(
        attemptDelaysSeconds: [Double] = warmupAttemptDelaysSeconds,
        fetch: (() async throws -> Void)? = nil
    ) async {
        for delaySeconds in attemptDelaysSeconds {
            if delaySeconds > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            }
            do {
                if let fetch {
                    try await fetch()
                } else {
                    #if canImport(FirebaseAppCheck)
                    _ = try await AppCheck.appCheck().token(forcingRefresh: false)
                    #endif
                }
                return
            } catch {
                continue
            }
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
                userInfo: [NSLocalizedDescriptionKey: "App Check debug token is not registered for this Firebase project. In the Xcode console, find \"App Check debug token: '…'\", register it in Firebase Console → App Check → Manage debug tokens, then relaunch. To avoid registering a new token per simulator, set an AppCheckDebugToken environment variable in your Run scheme to one shared token."]
            )
        }
        return error
    }
}
