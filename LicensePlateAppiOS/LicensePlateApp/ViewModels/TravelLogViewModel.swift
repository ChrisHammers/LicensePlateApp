//
//  TravelLogViewModel.swift
//  LicensePlateApp
//
//  Step 07 — ViewModel for Travel Log. Loads entries and builds rich summary on selection; no direct Firebase or ModelContext.
//

import Foundation
import Combine

@MainActor
final class TravelLogViewModel: ObservableObject {
    @Published private(set) var entries: [TravelLogEntry] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedSummary: TripSummary?
    @Published var isLoadingSummary = false

    private let travelLogRepository: TravelLogRepositoryProtocol
    private let tripSessionRepository: TripSessionRepositoryProtocol
    private let gameInstanceRepository: GameInstanceRepositoryProtocol
    private let tripActivityEventRepository: TripActivityEventRepositoryProtocol
    private var authService: FirebaseAuthService
    private let usePreviewEntries: Bool

    init(
        travelLogRepository: TravelLogRepositoryProtocol,
        tripSessionRepository: TripSessionRepositoryProtocol,
        gameInstanceRepository: GameInstanceRepositoryProtocol,
        tripActivityEventRepository: TripActivityEventRepositoryProtocol,
        authService: FirebaseAuthService,
        previewEntries: [TravelLogEntry]? = nil
    ) {
        self.travelLogRepository = travelLogRepository
        self.tripSessionRepository = tripSessionRepository
        self.gameInstanceRepository = gameInstanceRepository
        self.tripActivityEventRepository = tripActivityEventRepository
        self.authService = authService
        self.usePreviewEntries = previewEntries != nil
        if let entries = previewEntries {
            self.entries = entries
        }
    }

    func setAuthService(_ service: FirebaseAuthService) {
        self.authService = service
    }

    var currentUserId: String? {
        authService.currentUser?.firebaseUID ?? authService.currentUser?.id
    }

    /// Load travel log entries (ended and optionally cancelled). Call after repository context is set.
    func loadEntries(statusFilter: TravelLogStatusFilter = .endedAndCancelled) {
        if usePreviewEntries { return }
        isLoading = true
        errorMessage = nil
        let userId = currentUserId
        do {
            entries = try travelLogRepository.getSummaryProjections(
                userId: userId,
                sortBy: .endedAtDesc,
                limit: 100,
                statusFilter: statusFilter
            )
        } catch {
            errorMessage = error.localizedDescription
            entries = []
        }
        isLoading = false
    }

    /// Open summary for a session: fetch session, games, discoveries from event repo; compute credits; build and set selectedSummary.
    func openSummary(sessionId: UUID) {
        FeedbackService.shared.buttonTap()
        isLoadingSummary = true
        selectedSummary = nil
        errorMessage = nil
        defer { isLoadingSummary = false }

        do {
            guard let session = try tripSessionRepository.session(byId: sessionId) else {
                errorMessage = "Trip not found".localized
                return
            }
            let games = try gameInstanceRepository.fetchByTripSession(sessionId: sessionId)
            let discoveries = try tripActivityEventRepository.discoveries(sessionId: sessionId, gameInstanceId: nil)
            let discoveriesByTarget = Dictionary(grouping: discoveries, by: \.targetId)
            let isShared = TripModeRulesEngine.creditType(for: session.mode) == .shared
            var credits: [GameCredit] = []
            for (_, targetDiscoveries) in discoveriesByTarget {
                let sorted = targetDiscoveries.sorted { $0.discoveredAt < $1.discoveredAt }
                guard let discovery = isShared ? sorted.last : sorted.first else { continue }
                let existing = isShared ? Array(sorted.dropLast()) : Array(sorted.dropFirst())
                credits.append(contentsOf: GameCreditCalculator.credits(for: session.mode, discovery: discovery, existingDiscoveriesForTarget: existing))
            }

            let summary = TripSummaryBuilder.build(
                session: session,
                games: games,
                discoveries: discoveries,
                credits: credits
            )
            selectedSummary = summary
            AnalyticsService.shared.log(.tripSummaryViewed(sessionId: sessionId.uuidString))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearSelection() {
        selectedSummary = nil
        errorMessage = nil
    }

    /// Call when Travel Log screen is shown (e.g. onAppear).
    func onScreenAppeared() {
        AnalyticsService.shared.log(.travelLogOpened)
    }
}
