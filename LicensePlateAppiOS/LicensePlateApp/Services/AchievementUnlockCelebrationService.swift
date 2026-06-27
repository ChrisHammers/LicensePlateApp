//
//  AchievementUnlockCelebrationService.swift
//  LicensePlateApp
//
//  Observes progression snapshots and queues rank/achievement celebration popups.
//

import Combine
import Foundation

@MainActor
final class AchievementUnlockCelebrationService: ObservableObject {

    static let shared = AchievementUnlockCelebrationService()

    private let catalogProvider: ProgressionCatalogProviding
    private let userProgressionService: UserProgressionService
    private let userProgressionRepository: UserProgressionRepository
    private let entitlementService: EntitlementService
    private let lifetimeStatsCoordinator: LifetimeStatsCoordinator
    private let publicLifetimeStatsRepository: PublicLifetimeStatsRepository
    private let xpLedger: XpLedgerRepository
    private let userAchievementRepository: UserAchievementRepository
    private let userAchievementRemoteRepository: UserAchievementRemoteRepository
    private let achievementUnlockSyncService: AchievementUnlockSyncService
    private let rewardPresenter: RewardPresenter
    private var cancellables = Set<AnyCancellable>()
    private var refreshWorkItem: DispatchWorkItem?

    private var user: AppUser?
    private var previousSnapshot: AchievementProgressSnapshot?
    private var hasBaseline = false
    private var persistedAchievementIds: Set<String> = []

    init(
        catalogProvider: ProgressionCatalogProviding = ProgressionCatalogProvider.shared,
        userProgressionService: UserProgressionService = .shared,
        userProgressionRepository: UserProgressionRepository = .shared,
        entitlementService: EntitlementService = .shared,
        lifetimeStatsCoordinator: LifetimeStatsCoordinator = .shared,
        publicLifetimeStatsRepository: PublicLifetimeStatsRepository = .shared,
        xpLedger: XpLedgerRepository = .shared,
        userAchievementRepository: UserAchievementRepository = .shared,
        userAchievementRemoteRepository: UserAchievementRemoteRepository = .shared,
        achievementUnlockSyncService: AchievementUnlockSyncService = .shared,
        rewardPresenter: RewardPresenter = .shared
    ) {
        self.catalogProvider = catalogProvider
        self.userProgressionService = userProgressionService
        self.userProgressionRepository = userProgressionRepository
        self.entitlementService = entitlementService
        self.lifetimeStatsCoordinator = lifetimeStatsCoordinator
        self.publicLifetimeStatsRepository = publicLifetimeStatsRepository
        self.xpLedger = xpLedger
        self.userAchievementRepository = userAchievementRepository
        self.userAchievementRemoteRepository = userAchievementRemoteRepository
        self.achievementUnlockSyncService = achievementUnlockSyncService
        self.rewardPresenter = rewardPresenter

        userProgressionService.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleRefresh() }
            .store(in: &cancellables)

        userProgressionRepository.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleRefresh() }
            .store(in: &cancellables)

        entitlementService.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleRefresh() }
            .store(in: &cancellables)

        lifetimeStatsCoordinator.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleRefresh() }
            .store(in: &cancellables)

        xpLedger.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleRefresh() }
            .store(in: &cancellables)

        userAchievementRepository.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleRefresh() }
            .store(in: &cancellables)

        userAchievementRemoteRepository.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleRefresh() }
            .store(in: &cancellables)
    }

    func configure(user: AppUser?) {
        refreshWorkItem?.cancel()
        self.user = user
        previousSnapshot = nil
        hasBaseline = false
        persistedAchievementIds = []
        userAchievementRemoteRepository.stopListening()
        guard let user else { return }
        let userId = user.firebaseUID ?? user.id
        lifetimeStatsCoordinator.onProfileAppear(userId: userId)
        userAchievementRemoteRepository.startListening(userId: userId)
        reloadPersistedAchievementIds(for: userId)
        scheduleRefresh()
    }

    func resetForSignOut() {
        refreshWorkItem?.cancel()
        refreshWorkItem = nil
        user = nil
        previousSnapshot = nil
        hasBaseline = false
        persistedAchievementIds = []
        userAchievementRemoteRepository.stopListening()
        achievementUnlockSyncService.resetForSignOut()
        rewardPresenter.reset()
    }

    private func scheduleRefresh() {
        refreshWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.refresh()
        }
        refreshWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    private func refresh() {
        guard let user else { return }
        let userId = user.firebaseUID ?? user.id
        reloadPersistedAchievementIds(for: userId)

        let lifetimeStats = lifetimeStatsCoordinator.stats
        let totalXp = resolveTotalXp(for: user)
        let localRecords = (try? userAchievementRepository.fetchRecords(forUserId: userId)) ?? [:]
        let snapshot = AchievementProgressSnapshotBuilder.build(
            user: user,
            lifetimeStats: lifetimeStats,
            totalXp: totalXp,
            catalogProvider: catalogProvider,
            userProgressionService: userProgressionService,
            entitlementService: entitlementService,
            localPersistedRecords: localRecords,
            remotePersistedRecords: userAchievementRemoteRepository.records
        )

        guard isHydrated(for: user) else {
            previousSnapshot = snapshot
            return
        }

        guard hasBaseline, let previousSnapshot else {
            establishBaseline(snapshot: snapshot, userId: userId)
            return
        }

        let catalog = catalogProvider.current
        let ladder = ProgressionCatalogProjection.rankLadder(from: catalog)
        let achievementsById = Dictionary(uniqueKeysWithValues: ProgressionCatalogProjection.achievements(from: catalog).map { ($0.id, $0) })

        if catalog.presentation.rankProgressionEnabled,
           let newLevel = AchievementUnlockTransitionDetector.rankUpLevel(
               previous: previousSnapshot.rankLevel,
               nextLevel: snapshot.rankLevel
           ),
           let rank = ladder.ranks.first(where: { $0.level == newLevel }) {
            rewardPresenter.show(.rankUp(rank))
            AnalyticsService.shared.log(
                .rankUpCelebrated(level: newLevel, totalXp: snapshot.totalXp)
            )
        }

        if catalog.presentation.achievementsEnabled {
            let unlockedIds = AchievementUnlockTransitionDetector.newlyUnlockedAchievementIds(
                previous: previousSnapshot.statuses,
                next: snapshot.statuses
            )
            let celebrateIds = AchievementProgressPersistence.filterNotYetPersisted(
                unlockedIds,
                persistedIds: persistedAchievementIds
            )
            for id in celebrateIds {
                guard let achievement = achievementsById[id],
                      let status = snapshot.statuses[id] else { continue }
                rewardPresenter.show(.achievement(achievement))
                AnalyticsService.shared.log(
                    .achievementUnlocked(
                        achievementId: id,
                        category: achievement.category.rawValue,
                        rarity: achievement.rarity.title
                    )
                )
                try? userAchievementRepository.recordUnlock(
                    userId: userId,
                    achievementId: id,
                    lastProgress: status.progress
                )
                persistedAchievementIds.insert(id)
                let entitlement = entitlementService.entitlementState(for: user)
                Task {
                    await achievementUnlockSyncService.syncUnlocks(
                        user: user,
                        entitlement: entitlement,
                        candidates: [AchievementUnlockSyncCandidate(achievementId: id, lastProgress: status.progress)]
                    )
                }
            }
            for (id, status) in snapshot.statuses where status.isUnlocked && persistedAchievementIds.contains(id) {
                try? userAchievementRepository.updateProgressIfUnlocked(
                    userId: userId,
                    achievementId: id,
                    lastProgress: status.progress
                )
            }
        }

        self.previousSnapshot = snapshot
    }

    private func establishBaseline(snapshot: AchievementProgressSnapshot, userId: String) {
        for (id, status) in snapshot.statuses where status.isUnlocked {
            try? userAchievementRepository.backfillIfMissing(
                userId: userId,
                achievementId: id,
                lastProgress: status.progress
            )
        }
        persistedAchievementIds = AchievementProgressPersistence.persistedAchievementIds(
            local: (try? userAchievementRepository.fetchRecords(forUserId: userId)) ?? [:],
            remote: userAchievementRemoteRepository.records
        )
        previousSnapshot = snapshot
        hasBaseline = true
        if let user {
            let entitlement = entitlementService.entitlementState(for: user)
            Task {
                await achievementUnlockSyncService.syncUnlockedStatuses(
                    user: user,
                    entitlement: entitlement,
                    statuses: snapshot.statuses
                )
            }
        }
    }

    private func reloadPersistedAchievementIds(for userId: String) {
        let local = (try? userAchievementRepository.fetchRecords(forUserId: userId)) ?? [:]
        persistedAchievementIds = AchievementProgressPersistence.persistedAchievementIds(
            local: local,
            remote: userAchievementRemoteRepository.records
        )
    }

    private func resolveTotalXp(for user: AppUser) -> Int {
        if let effective = userProgressionService.effectiveTotals {
            return max(0, effective.totalXp)
        }
        let userId = user.firebaseUID ?? user.id
        let server = userProgressionRepository.snapshot?.totalXp ?? 0
        guard let events = try? xpLedger.ledgerEvents(userId: userId) else {
            return max(0, server)
        }
        return max(0, server + LedgerPendingXpTotals.fromLedgerEvents(events).provisionalSum)
    }

    private func isHydrated(for user: AppUser) -> Bool {
        guard userProgressionRepository.hasReceivedInitialSnapshot else { return false }
        guard userProgressionService.effectiveTotals != nil else { return false }
        guard isLifetimeStatsHydrated(for: user) else { return false }
        return userAchievementRemoteRepository.hasReceivedInitialSnapshot
    }

    private func isLifetimeStatsHydrated(for user: AppUser) -> Bool {
        let userId = user.firebaseUID ?? user.id
        if publicLifetimeStatsRepository.hasReceivedInitialProfileSnapshot(forUserId: userId) {
            return true
        }
        if lifetimeStatsCoordinator.stats != nil,
           (try? publicLifetimeStatsRepository.cachedStatsFromDisk(forUserId: userId)) != nil {
            return true
        }
        return false
    }
}
