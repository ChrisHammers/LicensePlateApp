//
//  LifetimeStatsCoordinator.swift
//  LicensePlateApp
//
//  MainActor: server-first public lifetime stats (Firestore listener + cache), local recompute as offline / repair fallback.
//

import Foundation
import SwiftData
import Combine

@MainActor
final class LifetimeStatsCoordinator: ObservableObject {

    static let shared = LifetimeStatsCoordinator()

    var authService: FirebaseAuthService?

    @Published private(set) var stats: UserLifetimeStats?
    @Published private(set) var isPendingServerSync: Bool = false
    /// True only while a full local recompute (fallback) is running.
    @Published private(set) var isRecomputing = false
    @Published private(set) var lastError: String?

    private let tripSessionRepository: TripSessionRepositoryProtocol
    private let gameInstanceRepository: GameInstanceRepositoryProtocol
    private let tripActivityEventRepository: TripActivityEventRepositoryProtocol
    private let userLifetimeStatsRepository: UserLifetimeStatsRepository
    private let familyMemberUserIdsRepository: FamilyMemberUserIdsRepository
    private let friendUserIdsRepository: FriendUserIdsRepository
    let publicLifetimeStatsRepository: PublicLifetimeStatsRepository

    private var boundProfileUserId: String?
    private var pendingUserId: String?
    private var awaitingServerAfterLocalTripEnd = false
    private var cancellables = Set<AnyCancellable>()

    private static let archivedTripFetchLimit = 50_000

    init(
        tripSessionRepository: TripSessionRepositoryProtocol = TripSessionRepository.shared,
        gameInstanceRepository: GameInstanceRepositoryProtocol = GameInstanceRepository.shared,
        tripActivityEventRepository: TripActivityEventRepositoryProtocol = TripActivityEventRepository.shared,
        userLifetimeStatsRepository: UserLifetimeStatsRepository = .shared,
        familyMemberUserIdsRepository: FamilyMemberUserIdsRepository = .shared,
        friendUserIdsRepository: FriendUserIdsRepository = .shared,
        publicLifetimeStatsRepository: PublicLifetimeStatsRepository = .shared
    ) {
        self.tripSessionRepository = tripSessionRepository
        self.gameInstanceRepository = gameInstanceRepository
        self.tripActivityEventRepository = tripActivityEventRepository
        self.userLifetimeStatsRepository = userLifetimeStatsRepository
        self.familyMemberUserIdsRepository = familyMemberUserIdsRepository
        self.friendUserIdsRepository = friendUserIdsRepository
        self.publicLifetimeStatsRepository = publicLifetimeStatsRepository

        publicLifetimeStatsRepository.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshDisplayedStats()
            }
            .store(in: &cancellables)
    }

    func loadCachedStats(forUserId userId: String) {
        lastError = nil
        do {
            _ = try userLifetimeStatsRepository.fetch(forUserId: userId)
        } catch {
            lastError = error.localizedDescription
        }
        _ = try? publicLifetimeStatsRepository.cachedStatsFromDisk(forUserId: userId)
        refreshDisplayedStats()
    }

    func onProfileAppear(userId: String) {
        boundProfileUserId = userId
        publicLifetimeStatsRepository.setProfileUserId(userId)
        publicLifetimeStatsRepository.ensureObservingProfileUser(userId)
        loadCachedStats(forUserId: userId)
        if authService?.isOnline == false {
            requestFallbackRecompute(userId: userId)
        }
    }

    func clearError() {
        lastError = nil
    }

    /// Local gameplay ended while online: server aggregate updates asynchronously.
    func onLocalTripEnded(userId: String) {
        let selfId = authService?.currentUser?.firebaseUID ?? authService?.currentUser?.id
        guard selfId == userId else { return }
        publicLifetimeStatsRepository.ensureObservingProfileUser(userId)
        guard userId == boundProfileUserId else { return }
        awaitingServerAfterLocalTripEnd = true
        if authService?.isOnline == false {
            requestFallbackRecompute(userId: userId)
        }
        refreshDisplayedStats()
        AnalyticsService.shared.log(.lifetimeStatsPendingSyncShown(surface: "trip_end"))
    }

    /// Full local recompute (offline repair / explicit retry). Not the hot path when online.
    func requestFallbackRecompute(userId: String) {
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
                    requestFallbackRecompute(userId: next)
                }
            }
            do {
                let input = try buildRecomputeInput(userId: userId)
                let computed = try await Task.detached(priority: .utility) {
                    try LifetimeStatsRecomputeEngine.compute(input)
                }.value
                try userLifetimeStatsRepository.upsert(userId: userId, stats: computed)
                AnalyticsService.shared.log(
                    .lifetimeStatsRecomputeSucceeded(
                        completedTripCount: computed.totalCompletedTrips,
                        familyOnlyTripCount: computed.familyOnlyTripsCount,
                        friendsOnlyTripCount: computed.friendsOnlyTripsCount,
                        mixedFriendsFamilyTripCount: computed.mixedFriendsFamilyTripsCount,
                        entireFamilyTripCount: computed.entireFamilyTripsCount
                    )
                )
                AnalyticsService.shared.log(.lifetimeStatsFallbackRecomputeUsed(reason: "offline_or_retry"))
                refreshDisplayedStats()
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

    /// Backward-compatible name for view models (runs local recompute).
    func requestRefresh(userId: String) {
        requestFallbackRecompute(userId: userId)
    }

    private func refreshDisplayedStats() {
        guard let uid = boundProfileUserId else {
            stats = nil
            isPendingServerSync = false
            return
        }
        let liveServer = publicLifetimeStatsRepository.snapshot(forUserId: uid)
        let diskServer = try? publicLifetimeStatsRepository.cachedStatsFromDisk(forUserId: uid)
        let serverStats = liveServer ?? diskServer
        let local = try? userLifetimeStatsRepository.fetch(forUserId: uid)
        let serverDate = serverStats?.lastComputedAt

        if liveServer != nil {
            awaitingServerAfterLocalTripEnd = false
        }

        isPendingServerSync = LifetimeStatsPendingSyncState.shouldShowPending(
            isAwaitingServerAfterLocalTripEnd: awaitingServerAfterLocalTripEnd,
            local: local,
            serverDocumentUpdatedAt: serverDate
        )

        if isPendingServerSync, let local {
            stats = local
        } else if let serverStats {
            stats = serverStats
        } else {
            stats = local
        }
    }

    private func buildRecomputeInput(userId: String) throws -> LifetimeStatsRecomputeInput {
        let familyIds = try familyMemberUserIdsRepository.activeFamilyMemberUserIds(forAppUserId: userId)
        let friendIds = try friendUserIdsRepository.activeFriendUserIds(forAppUserId: userId)
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
            friendUserIds: friendIds,
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
