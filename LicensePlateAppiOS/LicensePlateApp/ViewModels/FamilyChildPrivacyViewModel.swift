//
//  FamilyChildPrivacyViewModel.swift
//  LicensePlateApp
//
//  COPPA F-8 (FR-29): state for the read-only "Child privacy" detail.
//
//  The MUST half of FR-29 — current status plus the static summary of held data
//  categories — is pure copy rendered by the view. Consent history is the SHOULD half:
//  it comes from the manager-gated `getParentalConsentStatus` callable, and a failure
//  degrades to an explanatory row. The parent's review right is never blocked on it.
//

import Foundation
import Combine

@MainActor
final class FamilyChildPrivacyViewModel: ObservableObject {
    enum HistoryState: Equatable {
        case idle
        case loading
        case loaded([ParentalConsentRecord])
        case unavailable
    }

    @Published private(set) var historyState: HistoryState = .idle

    private let loadConsentHistory: (String) async throws -> ParentalConsentStatus

    init(loadConsentHistory: @escaping (String) async throws -> ParentalConsentStatus) {
        self.loadConsentHistory = loadConsentHistory
    }

    func load(childUserId: String) async {
        guard historyState == .idle else { return }
        historyState = .loading
        do {
            let status = try await loadConsentHistory(childUserId)
            historyState = .loaded(status.records)
        } catch {
            historyState = .unavailable
        }
    }

    /// Newest first — the current consent state is what a parent looks for.
    var recordsNewestFirst: [ParentalConsentRecord] {
        guard case .loaded(let records) = historyState else { return [] }
        return records.sorted { lhs, rhs in
            (lhs.createdAt ?? .distantPast) > (rhs.createdAt ?? .distantPast)
        }
    }
}
