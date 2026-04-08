//
//  ActiveTripsListViewModel.swift
//  LicensePlateApp
//
//  Step 05 — ViewModel for ContentView active trips list. Loads list, deletes via lifecycle, surfaces save failures.
//

import Foundation
import Combine

/// Item for the Active Trips list: session and trip-level rollup (game-scoped progress via rollup.primaryGame*).
struct ActiveListItem: Identifiable {
    var id: UUID { session.id }
    let session: TripSession
    let rollup: TripRollup
}

@MainActor
final class ActiveTripsListViewModel: ObservableObject {

    @Published private(set) var items: [ActiveListItem] = []
    @Published private(set) var errorMessage: String? = nil
    /// Step 14 — Shown when the user has a pending trip leave waiting to sync.
    @Published private(set) var pendingLeaveSyncHint: String? = nil

    private let tripSessionRepository: TripSessionRepositoryProtocol
    private let tripActivityEventRepository: TripActivityEventRepositoryProtocol
    private let gameInstanceRepository: GameInstanceRepositoryProtocol
    private let lifecycleService: TripSessionLifecycleServiceProtocol
    private let participationService: TripParticipationServiceProtocol

    /// Session IDs that failed to delete; retry uses these.
    private(set) var pendingDeleteSessionIds: [UUID] = []
    private(set) var pendingUserId: String?

    init(
        tripSessionRepository: TripSessionRepositoryProtocol,
        tripActivityEventRepository: TripActivityEventRepositoryProtocol,
        gameInstanceRepository: GameInstanceRepositoryProtocol,
        lifecycleService: TripSessionLifecycleServiceProtocol,
        participationService: TripParticipationServiceProtocol = TripParticipationService.shared
    ) {
        self.tripSessionRepository = tripSessionRepository
        self.tripActivityEventRepository = tripActivityEventRepository
        self.gameInstanceRepository = gameInstanceRepository
        self.lifecycleService = lifecycleService
        self.participationService = participationService
    }

    func load(userId: String?) {
        errorMessage = nil
        if let uid = userId {
            let pending = (try? PendingTripLeaveRepository.shared.sessionIdsPendingLeave(userId: uid)) ?? []
            pendingLeaveSyncHint = pending.isEmpty
                ? nil
                : "Some trip changes will sync when you are back online.".localized
        } else {
            pendingLeaveSyncHint = nil
        }
        do {
            let sessions = try tripSessionRepository.loadActiveSessions(userId: userId)
            let sorted = sessions.sorted { ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast) }
            var list: [ActiveListItem] = []
            for session in sorted {
                let games = (try? gameInstanceRepository.fetchByTripSession(sessionId: session.id)) ?? []
                let discoveries = (try? tripActivityEventRepository.discoveries(sessionId: session.id, gameInstanceId: nil)) ?? []
                let rollup = TripRollup.build(session: session, games: games, discoveries: discoveries)
                list.append(ActiveListItem(session: session, rollup: rollup))
            }
            items = list
            Task { @MainActor in
                LifetimeStatsCoordinator.shared.scheduleDebouncedLifetimeStatsRefresh()
            }
        } catch {
            errorMessage = error.localizedDescription
            items = []
        }
    }

    func deleteSessions(at offsets: IndexSet, userId: String?) {
        let sessionIds = offsets.map { items[$0].session.id }
        guard !sessionIds.isEmpty else { return }

        errorMessage = nil
        pendingDeleteSessionIds = []
        pendingUserId = nil

        guard let uid = userId else { return }

        do {
            for sessionId in sessionIds {
                guard let session = try tripSessionRepository.session(byId: sessionId) else { continue }
                if session.createdBy == uid {
                    try lifecycleService.cancelSession(sessionId: sessionId, cancelledBy: uid)
                } else {
                    try participationService.initiateLeaveTrip(sessionId: sessionId, userId: uid)
                }
            }
            load(userId: userId)
        } catch {
            pendingDeleteSessionIds = sessionIds
            pendingUserId = userId
            load(userId: uid)
            errorMessage = error.localizedDescription
            AnalyticsService.shared.log(.persistenceSaveFailed(context: "active_list_delete_or_leave", error: error.localizedDescription))
        }
    }

    func retryLastDelete() {
        guard !pendingDeleteSessionIds.isEmpty, let userId = pendingUserId else {
            clearError()
            return
        }
        let ids = pendingDeleteSessionIds
        pendingDeleteSessionIds = []
        pendingUserId = nil
        errorMessage = nil

        do {
            for sessionId in ids {
                guard let session = try tripSessionRepository.session(byId: sessionId) else { continue }
                if session.createdBy == userId {
                    try lifecycleService.cancelSession(sessionId: sessionId, cancelledBy: userId)
                } else {
                    try participationService.initiateLeaveTrip(sessionId: sessionId, userId: userId)
                }
            }
            load(userId: userId)
        } catch {
            pendingDeleteSessionIds = ids
            pendingUserId = userId
            load(userId: userId)
            errorMessage = error.localizedDescription
            AnalyticsService.shared.log(.persistenceSaveFailed(context: "active_list_delete_or_leave", error: error.localizedDescription))
        }
    }

    func clearError() {
        errorMessage = nil
    }

    /// Session by id; nil if not found. Used for TripSessionView / missing check.
    func session(for sessionId: UUID) -> TripSession? {
        try? tripSessionRepository.session(byId: sessionId)
    }

    /// Resolve session and specific game by ids. Used for coordinator .game(sessionId, gameId) destination.
    func sessionAndGame(sessionId: UUID, gameId: UUID) -> (TripSession, GameInstance)? {
        guard let session = try? tripSessionRepository.session(byId: sessionId) else { return nil }
        let games = (try? gameInstanceRepository.fetchByTripSession(sessionId: sessionId)) ?? []
        guard let game = games.first(where: { $0.id == gameId }) else { return nil }
        return (session, game)
    }
}
