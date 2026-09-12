//
//  DeviceTransferViewModels.swift
//  LicensePlateApp
//
//  COPPA v3 FR-84 (F-41) — parent-initiated device transfer for a consented child.
//
//  Two view models, one per side of the same code, kept in one file because neither is
//  meaningful without the other and a reader debugging a transfer needs both in front of them.
//
//  ANALYTICS, FR-21. `IssueDeviceTransferCodeViewModel` runs on the GUARDIAN's own instance
//  and logs a typed event; `AdoptDeviceTransferViewModel` runs only on a child's device and
//  logs NOTHING — no success event, no failure event, no error string. An event that can only
//  fire from a child session is the exact shape FR-21 forbids, and a failure event would be
//  the most tempting one to add.
//

import Combine
import Foundation
import SwiftUI
import UIKit

// MARK: - Guardian side

@MainActor
final class IssueDeviceTransferCodeViewModel: ObservableObject {
    @Published private(set) var code: String?
    @Published private(set) var expiresAt: Date?
    @Published private(set) var isGenerating = false
    @Published var errorMessage: String?
    @Published var showError = false
    /// Drives the countdown label; refreshed by the sheet's one-second timer.
    @Published private(set) var now: Date = .now

    let childUserId: String
    let childDisplayName: String
    private let familyId: String
    private let familyRepository: FamilyRepository

    init(
        childUserId: String,
        childDisplayName: String,
        familyId: String,
        familyRepository: FamilyRepository = .shared
    ) {
        self.childUserId = childUserId
        self.childDisplayName = childDisplayName
        self.familyId = familyId
        self.familyRepository = familyRepository
    }

    /// Seconds left, floored at zero. `nil` until a code exists.
    var secondsRemaining: Int? {
        guard let expiresAt else { return nil }
        return max(0, Int(expiresAt.timeIntervalSince(now).rounded(.down)))
    }

    var isExpired: Bool {
        guard let secondsRemaining else { return false }
        return secondsRemaining == 0
    }

    var formattedTimeRemaining: String? {
        guard let secondsRemaining else { return nil }
        let minutes = secondsRemaining / 60
        let seconds = secondsRemaining % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    func tickClock() {
        now = .now
    }

    /// Owned here rather than in the view, matching `CreateFamilyShareCodeViewModel.copyCode`
    /// — writing to the pasteboard is a side effect, and views render (CLAUDE.md).
    func copyCode() {
        guard let code else { return }
        UIPasteboard.general.string = code
    }

    func generateCode() {
        guard !isGenerating else { return }
        isGenerating = true
        Task {
            defer { isGenerating = false }
            do {
                let result = try await familyRepository.createDeviceTransferCode(
                    childUserId: childUserId,
                    familyId: familyId
                )
                code = result.code
                expiresAt = result.expiresAt
                now = .now
                // Guardian's own instance — see the FR-21 note in the file header.
                AnalyticsService.shared.log(.deviceTransferCodeIssued)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

// MARK: - Child side (new device)

@MainActor
final class AdoptDeviceTransferViewModel: ObservableObject {
    @Published var enteredCode: String = ""
    @Published private(set) var isRedeeming = false
    @Published private(set) var didAdopt = false
    @Published var errorMessage: String?
    @Published var showError = false

    private weak var authService: FirebaseAuthService?

    func configure(authService: FirebaseAuthService) {
        self.authService = authService
    }

    var canSubmit: Bool {
        !enteredCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isRedeeming
    }

    /// Normalizes to the uppercase alphabet the server generates, so a child typing lowercase
    /// is not told their correct code is wrong.
    func normalizeEnteredCode() {
        let uppercased = enteredCode.uppercased()
        if uppercased != enteredCode {
            enteredCode = uppercased
        }
    }

    func adopt() {
        guard let authService, canSubmit else { return }
        let code = enteredCode.trimmingCharacters(in: .whitespacesAndNewlines)
        isRedeeming = true
        Task {
            defer { isRedeeming = false }
            do {
                _ = try await authService.adoptTransferredChildIdentity(code: code)
                didAdopt = true
            } catch {
                // Surfaced, never logged (FR-21). The server's own wording is already the
                // single indistinguishable refusal — it deliberately does not say WHY, so
                // there is nothing here worth translating into a more specific message.
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}
