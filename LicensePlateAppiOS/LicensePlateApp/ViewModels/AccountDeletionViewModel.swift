//
//  AccountDeletionViewModel.swift
//  LicensePlateApp
//
//  UI state for the in-app account deletion flow (Guideline 5.1.1(v)).
//  Server deletion runs through AccountDeletionService; local teardown through
//  FirebaseAuthService.finalizeDeletedAccountLocally(). Views render phases only.
//

import Foundation
import Combine
import UIKit

@MainActor
final class AccountDeletionViewModel: ObservableObject {

    enum Phase: Equatable {
        case idle
        case deleting
        /// Firebase needs a fresh sign-in before the destructive call succeeds.
        case reauthRequired
        case reauthenticating
        case completed
    }

    @Published private(set) var phase: Phase = .idle
    @Published var hasAcknowledgedConsequences = false
    @Published var errorMessage: String?

    private let authService: FirebaseAuthService
    private let deletionService: AccountDeletionService
    private let analytics: AnalyticsLogging

    init(
        authService: FirebaseAuthService,
        deletionService: AccountDeletionService = .shared,
        analytics: AnalyticsLogging = AnalyticsService.shared
    ) {
        self.authService = authService
        self.deletionService = deletionService
        self.analytics = analytics
    }

    var isBusy: Bool {
        phase == .deleting || phase == .reauthenticating
    }

    /// Re-auth options matching the account's linked platforms.
    var reauthMethods: [AccountDeletionPolicy.ReauthMethod] {
        AccountDeletionPolicy.reauthMethods(forProviderIDs: authService.linkedAuthProviderIDs)
    }

    func onAppear() {
        analytics.log(.screenView(screenName: "delete_account", screenClass: "DeleteAccountView"))
    }

    /// Called after the user passed the acknowledgement toggle and the final
    /// destructive confirmation alert.
    func deleteAccountConfirmed() {
        guard !isBusy, phase != .completed else { return }
        analytics.log(.accountDeletionRequested)
        Task { await performDeletion() }
    }

    // MARK: - Re-authentication

    func reauthenticateWithApple() {
        performReauthentication { [authService] in
            try await authService.reauthenticateWithApple()
        }
    }

    func reauthenticateWithGoogle(presentingViewController: UIViewController) {
        performReauthentication { [authService] in
            try await authService.reauthenticateWithGoogle(presentingViewController: presentingViewController)
        }
    }

    func reauthenticate(email: String, password: String) {
        performReauthentication { [authService] in
            try await authService.reauthenticate(email: email, password: password)
        }
    }

    private func performReauthentication(_ operation: @escaping () async throws -> Void) {
        guard phase == .reauthRequired else { return }
        phase = .reauthenticating
        errorMessage = nil
        Task {
            do {
                try await operation()
                // auth_time is fresh again — retry the deletion the user already confirmed.
                await performDeletion()
            } catch {
                phase = .reauthRequired
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Deletion

    private func performDeletion() async {
        phase = .deleting
        errorMessage = nil

        do {
            try await deletionService.deleteAccountOnServer()
        } catch let error as AccountDeletionError {
            switch error {
            case .recentLoginRequired:
                analytics.log(.accountDeletionReauthRequired)
                phase = .reauthRequired
            case .offline:
                analytics.log(.accountDeletionFailed(error: "offline"))
                phase = .idle
                errorMessage = error.localizedDescription
            case .serverError:
                analytics.log(.accountDeletionFailed(error: "server_error"))
                phase = .idle
                errorMessage = error.localizedDescription
            }
            return
        } catch {
            analytics.log(.accountDeletionFailed(error: "unknown"))
            phase = .idle
            errorMessage = error.localizedDescription
            return
        }

        // Server-side deletion succeeded — never fall back to a retry state here,
        // and never write to Firestore as the deleted user during teardown.
        do {
            try await authService.finalizeDeletedAccountLocally()
        } catch {
            analytics.log(.accountDeletionFailed(error: "local_finalize_failed"))
        }
        analytics.log(.accountDeletionCompleted)
        phase = .completed
    }
}
