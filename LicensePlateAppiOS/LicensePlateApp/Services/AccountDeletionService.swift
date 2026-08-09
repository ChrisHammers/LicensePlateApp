//
//  AccountDeletionService.swift
//  LicensePlateApp
//
//  In-app account deletion (App Review Guideline 5.1.1(v); ToS §15, Privacy Policy §11).
//  Calls the `deleteAccount` cloud function, which deletes the Firebase Auth user and
//  their personal cloud data. Local teardown afterwards is
//  `FirebaseAuthService.finalizeDeletedAccountLocally()`.
//

import Foundation
import FirebaseFunctions

// MARK: - Errors

enum AccountDeletionError: LocalizedError, Equatable {
    /// Firebase requires a fresh sign-in before destructive account operations;
    /// the caller should prompt re-authentication and retry.
    case recentLoginRequired
    case offline
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .recentLoginRequired:
            return "For your security, please verify it's you before deleting your account.".localized
        case .offline:
            return "You are currently offline. Please check your connection and try again.".localized
        case .serverError(let message):
            return message
        }
    }
}

// MARK: - Pure policy (unit-tested; no Firebase calls)

enum AccountDeletionPolicy {

    /// Re-authentication choices surfaced to the user.
    enum ReauthMethod: String, CaseIterable, Equatable {
        case apple
        case google
        case emailPassword
    }

    /// Maps the account's linked Firebase Auth provider IDs to the re-auth options
    /// offered, ordered Apple → Google → email/password. Unknown providers are dropped.
    static func reauthMethods(forProviderIDs providerIDs: [String]) -> [ReauthMethod] {
        let mapping: [(id: String, method: ReauthMethod)] = [
            ("apple.com", .apple),
            ("google.com", .google),
            ("password", .emailPassword),
        ]
        var methods: [ReauthMethod] = []
        for entry in mapping where providerIDs.contains(entry.id) {
            if !methods.contains(entry.method) {
                methods.append(entry.method)
            }
        }
        return methods
    }

    /// The server rejects stale sessions with failed-precondition and
    /// details.reason == "recent-login-required" (see functions/src/accountDeletion.ts).
    static func isRecentLoginRequired(domain: String, code: Int, detailsReason: String?) -> Bool {
        domain == FunctionsErrorDomain
            && code == FunctionsErrorCode.failedPrecondition.rawValue
            && detailsReason == "recent-login-required"
    }

    /// Classifies a `deleteAccount` callable failure into the user-facing error.
    static func classifyServerError(domain: String, code: Int, detailsReason: String?, message: String) -> AccountDeletionError {
        if isRecentLoginRequired(domain: domain, code: code, detailsReason: detailsReason) {
            return .recentLoginRequired
        }
        if domain == FunctionsErrorDomain,
           FunctionsErrorCode(rawValue: code) == .unavailable {
            return .offline
        }
        return .serverError(message)
    }
}

// MARK: - Service

@MainActor
final class AccountDeletionService {
    static let shared = AccountDeletionService()

    private init() {}

    /// Calls the `deleteAccount` cloud function. `clientMetadata` rides as a sibling
    /// field (client-metadata-cloud-calls rule). Throws `AccountDeletionError`.
    func deleteAccountOnServer() async throws {
        do {
            let fn = Functions.functions().httpsCallable("deleteAccount")
            _ = try await fn.call(([:] as [String: Any]).addingClientMetadata())
        } catch {
            throw Self.mapServerError(error)
        }
    }

    nonisolated static func mapServerError(_ error: Error) -> AccountDeletionError {
        let nsError = error as NSError
        let details = nsError.userInfo[FunctionsErrorDetailsKey] as? [String: Any]
        let reason = details?["reason"] as? String
        let message = (nsError.userInfo[NSLocalizedDescriptionKey] as? String)
            ?? error.localizedDescription
        return AccountDeletionPolicy.classifyServerError(
            domain: nsError.domain,
            code: nsError.code,
            detailsReason: reason,
            message: message
        )
    }
}
