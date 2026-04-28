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
    /// Recap sheet / `openSummary` only; kept separate from Travel Log list `errorMessage`.
    @Published var summaryErrorMessage: String?
    @Published var selectedSummary: TripSummary?
    @Published var isLoadingSummary = false
    @Published private(set) var hiddenSavedTripCount = 0
    @Published var shouldPresentSavedTripPaywall = false
    @Published private(set) var savedTripCapKind: SavedTripCapKind = .unlimited
    @Published private(set) var shouldShowTravelLogAd = false

    /// Avoid duplicate section analytics if `onAppear` fires more than once for the same recap.
    private var recapSectionAnalyticsLoggedSessionId: UUID?

    private let travelLogRepository: TravelLogRepositoryProtocol
    private let tripSessionRepository: TripSessionRepositoryProtocol
    private let gameInstanceRepository: GameInstanceRepositoryProtocol
    private let tripActivityEventRepository: TripActivityEventRepositoryProtocol
    private let xpLedger: XpLedgerRepositoryProtocol
    private let savedTripAccessPolicy: SavedTripAccessPolicy
    private let analytics: AnalyticsLogging
    private var authService: FirebaseAuthService
    private let usePreviewEntries: Bool
    private var savedTripLimitAnalyticsSignature: String?

    init(
        travelLogRepository: TravelLogRepositoryProtocol,
        tripSessionRepository: TripSessionRepositoryProtocol,
        gameInstanceRepository: GameInstanceRepositoryProtocol,
        tripActivityEventRepository: TripActivityEventRepositoryProtocol,
        authService: FirebaseAuthService,
        xpLedger: XpLedgerRepositoryProtocol = XpLedgerRepository.shared,
        savedTripAccessPolicy: SavedTripAccessPolicy = .shared,
        analytics: AnalyticsLogging = AnalyticsService.shared,
        previewEntries: [TravelLogEntry]? = nil,
        previewHiddenSavedTripCount: Int = 0,
        previewSavedTripCapKind: SavedTripCapKind = .unlimited
    ) {
        self.travelLogRepository = travelLogRepository
        self.tripSessionRepository = tripSessionRepository
        self.gameInstanceRepository = gameInstanceRepository
        self.tripActivityEventRepository = tripActivityEventRepository
        self.xpLedger = xpLedger
        self.savedTripAccessPolicy = savedTripAccessPolicy
        self.analytics = analytics
        self.authService = authService
        self.usePreviewEntries = previewEntries != nil
        if let entries = previewEntries {
            self.entries = entries
            self.hiddenSavedTripCount = previewHiddenSavedTripCount
            self.savedTripCapKind = previewSavedTripCapKind
        }
    }

    func setAuthService(_ service: FirebaseAuthService) {
        self.authService = service
    }

    var currentUserId: String? {
        authService.currentUser?.firebaseUID ?? authService.currentUser?.id
    }

    var visibleSavedTripLimit: Int? {
        savedTripAccessPolicy.visibleSavedTripLimit(for: authService.currentUser)
    }

    var isCurrentUserAnonymous: Bool {
        savedTripCapKind == .anonymous
    }

    /// Load travel log entries (ended and optionally cancelled). Call after repository context is set.
    func loadEntries(statusFilter: TravelLogStatusFilter = .endedAndCancelled) {
        if usePreviewEntries { return }
        isLoading = true
        errorMessage = nil
        let userId = currentUserId
        do {
            let fetchedEntries = try travelLogRepository.getSummaryProjections(
                userId: userId,
                sortBy: .endedAtDesc,
                limit: 100,
                statusFilter: statusFilter
            )
            applySavedTripCap(to: fetchedEntries)
        } catch {
            errorMessage = error.localizedDescription
            entries = []
            hiddenSavedTripCount = 0
        }
        isLoading = false
    }

    func showSavedTripLimitPaywall() {
        FeedbackService.shared.buttonTap()
        shouldPresentSavedTripPaywall = true
    }

    func dismissSavedTripPaywall() {
        shouldPresentSavedTripPaywall = false
    }

    private func applySavedTripCap(to fetchedEntries: [TravelLogEntry]) {
        savedTripCapKind = savedTripAccessPolicy.savedTripCapKind(for: authService.currentUser)
        guard let limit = savedTripAccessPolicy.visibleSavedTripLimit(for: authService.currentUser) else {
            entries = fetchedEntries
            hiddenSavedTripCount = 0
            return
        }

        entries = Array(fetchedEntries.prefix(limit))
        hiddenSavedTripCount = max(0, fetchedEntries.count - limit)
        logSavedTripLimitHitIfNeeded(totalCount: fetchedEntries.count, limit: limit)
    }

    private func logSavedTripLimitHitIfNeeded(totalCount: Int, limit: Int) {
        guard hiddenSavedTripCount > 0 else { return }
        let tier = savedTripAccessPolicy.tierName(for: authService.currentUser)
        let signature = "\(totalCount)-\(limit)-\(tier)"
        guard signature != savedTripLimitAnalyticsSignature else { return }
        savedTripLimitAnalyticsSignature = signature
        analytics.log(.savedTripLimitHit(
            source: "travel_log",
            savedTripCount: totalCount,
            savedTripLimit: limit,
            tier: tier
        ))
    }

    /// Open summary for a session: fetch session, games, discoveries from event repo; compute credits; build and set selectedSummary. Recap is built from canonical data only: TripSession, GameInstance, and TripActivityEvent-derived discoveries and credits.
    func openSummary(sessionId: UUID) {
        FeedbackService.shared.buttonTap()
        isLoadingSummary = true
        selectedSummary = nil
        summaryErrorMessage = nil
        recapSectionAnalyticsLoggedSessionId = nil
        defer { isLoadingSummary = false }

        do {
            guard let session = try tripSessionRepository.session(byId: sessionId) else {
                summaryErrorMessage = "Trip not found".localized
                return
            }
            let games = try gameInstanceRepository.fetchByTripSession(sessionId: sessionId)
            let discoveries = try tripActivityEventRepository.discoveries(sessionId: sessionId, gameInstanceId: nil)
            var summary = TripSummaryBuilder.build(session: session, games: games, discoveries: discoveries)
            if let uid = currentUserId, !uid.isEmpty {
                let ledgerRows = (try? xpLedger.ledgerEvents(userId: uid, sessionId: sessionId)) ?? []
                let itemTitle: (String) -> String = { itemId in
                    PlateRegion.all.first { $0.id == itemId }?.name ?? itemId
                }
                summary.xpRecapLines = XpFeedProjectionBuilder.lines(from: ledgerRows, itemTitle: itemTitle)
            }
            selectedSummary = summary
            if summary.unassignedDiscoveryCount > 0 {
                AnalyticsService.shared.log(
                    .summaryProjectionMismatch(
                        sessionId: sessionId.uuidString,
                        error: "unassigned_discovery_count=\(summary.unassignedDiscoveryCount)"
                    )
                )
            }
            AnalyticsService.shared.log(.tripSummaryViewed(sessionId: sessionId.uuidString))
            if summary.hasCompetitiveGame {
                AnalyticsService.shared.log(.tripSummaryCompetitiveRankingsPresented(tripSessionId: sessionId.uuidString))
            }
        } catch {
            summaryErrorMessage = error.localizedDescription
        }
    }

    func clearSelection() {
        selectedSummary = nil
        summaryErrorMessage = nil
        recapSectionAnalyticsLoggedSessionId = nil
    }

    /// When the recap sheet is on screen — logs section-level analytics once per session presentation.
    func onRecapSheetAppeared(summary: TripSummary) {
        if recapSectionAnalyticsLoggedSessionId == summary.sessionId { return }
        recapSectionAnalyticsLoggedSessionId = summary.sessionId
        let sid = summary.sessionId.uuidString
        if !summary.games.isEmpty {
            AnalyticsService.shared.log(.tripSummaryViewedGameSection(sessionId: sid))
        }
        if !summary.rankedParticipants.isEmpty {
            AnalyticsService.shared.log(.tripSummaryViewedParticipantSection(sessionId: sid))
        }
        if let meta = summary.locationMetadata, !meta.isEmpty {
            AnalyticsService.shared.log(.tripSummaryViewedMapRecap(sessionId: sid))
        }
        if !summary.xpRecapLines.isEmpty {
            AnalyticsService.shared.log(.tripSummaryViewedXpRecap(sessionId: sid))
        }
    }

    /// Call when Travel Log screen is shown (e.g. onAppear).
    func onScreenAppeared() {
        AnalyticsService.shared.log(.travelLogOpened)
        AnalyticsService.shared.logScreenView(screenName: "travel_log")
        shouldShowTravelLogAd = AdEligibilityService.shared.shouldShowAd(for: .travelLog, user: authService.currentUser)
    }

    func shouldShowTripSummaryAd() -> Bool {
        AdEligibilityService.shared.shouldShowAd(for: .tripSummary, user: authService.currentUser)
    }
}
