//
//  LifetimeStatsCoordinator.swift
//  LicensePlateApp
//
//  MainActor: snapshot fetch via repos, single-flight refresh, background compute, persist, published UI state.
//

import Foundation
import SwiftData
import Combine

@MainActor
final class LifetimeStatsCoordinator: ObservableObject {

    static let shared = LifetimeStatsCoordinator()

    /// Set once from app bootstrap (`RootView.task`); same lifetime as other global services.
    var authService: FirebaseAuthService?

    @Published private(set) var stats: UserLifetimeStats?
    @Published private(set) var isRecomputing = false
    @Published private(set) var lastError: String?

    private let tripSessionRepository: TripSessionRepositoryProtocol
    private let gameInstanceRepository: GameInstanceRepositoryProtocol
    private let tripActivityEventRepository: TripActivityEventRepositoryProtocol
    private let userLifetimeStatsRepository: UserLifetimeStatsRepository
    private let familyMemberUserIdsRepository: FamilyMemberUserIdsRepository

    private var pendingUserId: String?
    private var debounceTask: Task<Void, Never>?

    private static let archivedTripFetchLimit = 50_000

    init(
        tripSessionRepository: TripSessionRepositoryProtocol = TripSessionRepository.shared,
        gameInstanceRepository: GameInstanceRepositoryProtocol = GameInstanceRepository.shared,
        tripActivityEventRepository: TripActivityEventRepositoryProtocol = TripActivityEventRepository.shared,
        userLifetimeStatsRepository: UserLifetimeStatsRepository = .shared,
        familyMemberUserIdsRepository: FamilyMemberUserIdsRepository = .shared
    ) {
        self.tripSessionRepository = tripSessionRepository
        self.gameInstanceRepository = gameInstanceRepository
        self.tripActivityEventRepository = tripActivityEventRepository
        self.userLifetimeStatsRepository = userLifetimeStatsRepository
        self.familyMemberUserIdsRepository = familyMemberUserIdsRepository
    }

    /// Load persisted row only (fast path for profile).
    func loadCachedStats(forUserId userId: String) {
        lastError = nil
        do {
            stats = try userLifetimeStatsRepository.fetch(forUserId: userId)
        } catch {
            lastError = error.localizedDescription
            stats = nil
        }
    }

    func onProfileAppear(userId: String) {
        loadCachedStats(forUserId: userId)
        requestRefresh(userId: userId)
    }

    func clearError() {
        lastError = nil
    }

    /// Uses `authService` to resolve the signed-in user id.
    func scheduleLifetimeStatsRefresh() {
        guard let uid = authService?.currentUser?.firebaseUID ?? authService?.currentUser?.id else { return }
        requestRefresh(userId: uid)
    }

    func scheduleDebouncedLifetimeStatsRefresh() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            scheduleLifetimeStatsRefresh()
        }
    }

    /// Single-flight with pending coalesce for the same or subsequent user id.
    func requestRefresh(userId: String) {
        if isRecomputing {
            pendingUserId = userId
            return
        }
        isRecomputing = true
        lastError = nil
        AnalyticsService.shared.log(.lifetimeStatsRecomputeStarted)

        Task { @MainActor in
            defer {
                isRecomputing = false
                if let next = pendingUserId {
                    pendingUserId = nil
                    requestRefresh(userId: next)
                }
            }
            do {
                let input = try buildRecomputeInput(userId: userId)
                let computed = try await Task.detached(priority: .utility) {
                    try LifetimeStatsRecomputeEngine.compute(input)
                }.value
                try userLifetimeStatsRepository.upsert(userId: userId, stats: computed)
                stats = computed
                UserLifetimeStatsCloudMirrorStub.scheduleUploadIfNeeded(userId: userId, stats: computed)
                AnalyticsService.shared.log(
                    .lifetimeStatsRecomputeSucceeded(
                        completedTripCount: computed.totalCompletedTrips,
                        familyOnlyTripCount: computed.familyOnlyTripsCount
                    )
                )
            } catch is CancellationError {
                // ignore
            } catch {
                lastError = error.localizedDescription
                AnalyticsService.shared.log(
                    .lifetimeStatsRecomputeFailed(error: String(describing: type(of: error)))
                )
            }
        }
    }

    private func buildRecomputeInput(userId: String) throws -> LifetimeStatsRecomputeInput {
        let familyIds = try familyMemberUserIdsRepository.activeFamilyMemberUserIds(forAppUserId: userId)
        let archived = try tripSessionRepository.loadArchivedSessions(
            userId: userId,
            limit: Self.archivedTripFetchLimit,
            includeCancelled: false,
            sortBy: .endedAtDesc
        )
        var trips: [LifetimeStatsTripInput] = []
        trips.reserveCapacity(archived.count)
        for session in archived {
            let games = try gameInstanceRepository.fetchByTripSession(sessionId: session.id)
            let discoveries = try tripActivityEventRepository.discoveries(sessionId: session.id, gameInstanceId: nil)
            let sessionSnap = LifetimeStatsSessionSnapshot(
                id: session.id,
                name: session.name,
                statusRaw: session.status.rawValue,
                createdAt: session.createdAt,
                createdBy: session.createdBy,
                startedAt: session.startedAt,
                endedAt: session.endedAt,
                endedBy: session.endedBy,
                participants: session.participants,
                riskFlags: session.riskFlags
            )
            let gameSnaps = games.map { Self.gameSnapshot($0) }
            trips.append(LifetimeStatsTripInput(session: sessionSnap, games: gameSnaps, discoveries: discoveries))
        }
        return LifetimeStatsRecomputeInput(
            subjectUserId: userId,
            familyMemberUserIds: familyIds,
            trips: trips
        )
    }

    private static func gameSnapshot(_ game: GameInstance) -> LifetimeStatsGameSnapshot {
        LifetimeStatsGameSnapshot(
            id: game.id,
            definitionId: game.definitionId,
            sessionId: game.sessionId,
            startedAt: game.startedAt,
            endedAt: game.endedAt,
            ruleSet: game.ruleSet,
            commonConfig: game.commonConfig,
            gameSpecificPayloadType: game.gameSpecificPayloadType,
            gameSpecificPayloadVersion: game.gameSpecificPayloadVersion,
            gameSpecificPayloadData: game.gameSpecificPayloadData,
            teams: game.teams,
            fairnessUiLastAckAt: game.fairnessUiLastAckAt
        )
    }
}
