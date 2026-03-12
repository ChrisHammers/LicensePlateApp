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
    private let tripRepository: TripRepositoryProtocol
    private var authService: FirebaseAuthService

    init(
        travelLogRepository: TravelLogRepositoryProtocol,
        tripSessionRepository: TripSessionRepositoryProtocol,
        gameInstanceRepository: GameInstanceRepositoryProtocol,
        tripRepository: TripRepositoryProtocol,
        authService: FirebaseAuthService
    ) {
        self.travelLogRepository = travelLogRepository
        self.tripSessionRepository = tripSessionRepository
        self.gameInstanceRepository = gameInstanceRepository
        self.tripRepository = tripRepository
        self.authService = authService
    }

    func setAuthService(_ service: FirebaseAuthService) {
        self.authService = service
    }

    var currentUserId: String? {
        authService.currentUser?.firebaseUID ?? authService.currentUser?.id
    }

    /// Load travel log entries (ended and optionally cancelled). Call after repository context is set.
    func loadEntries(statusFilter: TravelLogStatusFilter = .endedAndCancelled) {
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

    /// Open summary for a session: fetch session, games, and if legacy trip then discoveries/credits; build and set selectedSummary.
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
            var discoveries: [GameDiscovery] = []
            var credits: [GameCredit] = []

            if let legacyId = session.legacyTripId,
               let trip = try tripRepository.get(byId: legacyId) {
                let adapted = LegacyTripAdapter.adapt(trip)
                discoveries = adapted.discoveries
                credits = adapted.credits
                AnalyticsService.shared.log(.legacyTripAdapterUsed(legacyTripId: legacyId.uuidString, sessionId: sessionId.uuidString))
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
