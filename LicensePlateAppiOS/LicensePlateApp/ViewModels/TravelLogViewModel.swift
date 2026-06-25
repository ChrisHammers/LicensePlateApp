//
//  TravelLogViewModel.swift
//  LicensePlateApp
//
//  Step 07 — ViewModel for Travel Log. Loads entries and builds rich summary on selection; no direct Firebase or ModelContext.
//

import Foundation
import Combine

enum TripSummaryPresentationSource: String, Equatable, Sendable {
    case travelLog
    case localEnd
    case remoteEnd
}

enum TravelLogSummaryBuildError: LocalizedError {
    case tripNotFound
    case tripNotEnded

    var errorDescription: String? {
        switch self {
        case .tripNotFound:
            return "Trip not found".localized
        case .tripNotEnded:
            return "trip_summary.error.trip_not_ended".localized
        }
    }
}

@MainActor
final class TravelLogViewModel: ObservableObject {
    @Published private(set) var entries: [TravelLogEntry] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    /// Recap sheet / `openSummary` only; kept separate from Travel Log list `errorMessage`.
    @Published var summaryErrorMessage: String?
    @Published var selectedSummary: TripSummary?
    @Published var isLoadingSummary = false
    /// Where the recap sheet should appear (Travel Log sheet vs home root).
    @Published private(set) var summaryPresentationSource: TripSummaryPresentationSource?
    @Published private(set) var hiddenSavedTripCount = 0
    @Published var shouldPresentSavedTripPaywall = false
    @Published private(set) var savedTripCapKind: SavedTripCapKind = .unlimited
    @Published private(set) var shouldShowTravelLogAd = false

    /// Avoid duplicate section analytics if `onAppear` fires more than once for the same recap.
    private var recapSectionAnalyticsLoggedSessionId: UUID?

    /// Avoid duplicate auto-present when local end and remote `trip_ended` both arrive.
    private var autoPresentedSummarySessionIds: Set<UUID> = []

    private static let pendingAutoRecapDefaultsKey = "tripEnd.pendingAutoRecapSessionIds"

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

    func openSummary(sessionId: UUID, source: TripSummaryPresentationSource = .travelLog) {
        if source != .travelLog {
            guard !autoPresentedSummarySessionIds.contains(sessionId) else { return }
        }
        summaryPresentationSource = source
        if source == .travelLog {
            FeedbackService.shared.buttonTap()
        }
        isLoadingSummary = true
        selectedSummary = nil
        summaryErrorMessage = nil
        recapSectionAnalyticsLoggedSessionId = nil
        defer { isLoadingSummary = false }

        do {
            let summary = try buildSummary(sessionId: sessionId)
            selectedSummary = summary
            if source != .travelLog {
                autoPresentedSummarySessionIds.insert(sessionId)
                removePendingAutoRecap(sessionId: sessionId)
                analytics.log(.tripSummaryAutoPresentedAfterEnd(
                    sessionId: sessionId.uuidString,
                    source: source.rawValue
                ))
            }
            if summary.unassignedDiscoveryCount > 0 {
                analytics.log(
                    .summaryProjectionMismatch(
                        sessionId: sessionId.uuidString,
                        error: "unassigned_discovery_count=\(summary.unassignedDiscoveryCount)"
                    )
                )
            }
            analytics.log(.tripSummaryViewed(sessionId: sessionId.uuidString))
            if summary.hasCompetitiveGame {
                analytics.log(.tripSummaryCompetitiveRankingsPresented(tripSessionId: sessionId.uuidString))
            }
        } catch let error as TravelLogSummaryBuildError {
            summaryErrorMessage = error.localizedDescription
        } catch {
            summaryErrorMessage = error.localizedDescription
        }
    }

    func enqueuePendingAutoRecap(sessionId: UUID) {
        guard !autoPresentedSummarySessionIds.contains(sessionId) else { return }
        var pending = Self.loadPendingAutoRecapSessionIds()
        let id = sessionId.uuidString
        guard !pending.contains(id) else { return }
        pending.append(id)
        UserDefaults.standard.set(pending, forKey: Self.pendingAutoRecapDefaultsKey)
    }

    func flushPendingAutoRecapPresentations() {
        let pending = Self.loadPendingAutoRecapSessionIds()
        guard let first = pending.first, let sessionId = UUID(uuidString: first) else { return }
        if autoPresentedSummarySessionIds.contains(sessionId) {
            removePendingAutoRecap(sessionId: sessionId)
            return
        }
        openSummary(sessionId: sessionId, source: .remoteEnd)
    }

    private func removePendingAutoRecap(sessionId: UUID) {
        var pending = Self.loadPendingAutoRecapSessionIds()
        pending.removeAll { $0 == sessionId.uuidString }
        UserDefaults.standard.set(pending, forKey: Self.pendingAutoRecapDefaultsKey)
    }

    private static func loadPendingAutoRecapSessionIds() -> [String] {
        UserDefaults.standard.stringArray(forKey: pendingAutoRecapDefaultsKey) ?? []
    }

    private func buildSummary(sessionId: UUID) throws -> TripSummary {
        guard let session = try tripSessionRepository.session(byId: sessionId) else {
            throw TravelLogSummaryBuildError.tripNotFound
        }
        guard session.status == .ended else {
            throw TravelLogSummaryBuildError.tripNotEnded
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
        return summary
    }

    func clearSelection() {
        selectedSummary = nil
        summaryErrorMessage = nil
        recapSectionAnalyticsLoggedSessionId = nil
        summaryPresentationSource = nil
    }

    var presentsSummaryInTravelLog: Bool {
        summaryPresentationSource == .travelLog
    }

    var presentsSummaryAtRoot: Bool {
        guard let summaryPresentationSource else { return false }
        return summaryPresentationSource != .travelLog
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
