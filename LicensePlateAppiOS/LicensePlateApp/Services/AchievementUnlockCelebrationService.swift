//
//  AchievementUnlockCelebrationService.swift
//  LicensePlateApp
//
//  Observes progression snapshots and queues rank/achievement celebration popups.
//  Offline-capable: baselines historical state at attach, then celebrates in-session transitions.
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
    private let deliveryOutbox: RewardDeliveryOutbox
    private var cancellables = Set<AnyCancellable>()
    private var refreshWorkItem: DispatchWorkItem?

    private var user: AppUser?
    private var previousSnapshot: AchievementProgressSnapshot?
    private var firstSnapshotAfterConfigure: AchievementProgressSnapshot?
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
        rewardPresenter: RewardPresenter = .shared,
        deliveryOutbox: RewardDeliveryOutbox = .shared
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
        self.deliveryOutbox = deliveryOutbox

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
        firstSnapshotAfterConfigure = nil
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
        firstSnapshotAfterConfigure = nil
        hasBaseline = false
        persistedAchievementIds = []
        userAchievementRemoteRepository.stopListening()
        achievementUnlockSyncService.resetForSignOut()
        rewardPresenter.reset()
        XpClawbackPresentationService.shared.resetForSignOut()
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

        if firstSnapshotAfterConfigure == nil {
            firstSnapshotAfterConfigure = snapshot
        }

        guard isHydrated(for: user) else {
            return
        }

        if !hasBaseline {
            let baseline = firstSnapshotAfterConfigure ?? snapshot
            establishBaseline(snapshot: baseline, userId: userId)
            previousSnapshot = baseline
            hasBaseline = true
        }

        guard let previousSnapshot else { return }

        let catalog = catalogProvider.current
        let ladder = ProgressionCatalogProjection.rankLadder(from: catalog)
        let achievementsById = Dictionary(uniqueKeysWithValues: ProgressionCatalogProjection.achievements(from: catalog).map { ($0.id, $0) })

        if catalog.presentation.rankProgressionEnabled,
           let newLevel = AchievementUnlockTransitionDetector.rankUpLevel(
               previous: previousSnapshot.rankLevel,
               nextLevel: snapshot.rankLevel
           ),
           let rank = ladder.ranks.first(where: { $0.level == newLevel }) {
            let semanticId = "rank-\(newLevel)"
            if !deliveryOutbox.hasPresentedOrDismissed(userId: userId, semanticId: semanticId) {
                rewardPresenter.show(.rankUp(rank))
                deliveryOutbox.mark(userId: userId, semanticId: semanticId, state: .presented)
                AnalyticsService.shared.log(
                    .rankUpCelebrated(level: newLevel, totalXp: snapshot.totalXp)
                )
            }
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
                let semanticId = "ach-\(id)"
                if deliveryOutbox.hasPresentedOrDismissed(userId: userId, semanticId: semanticId) {
                    continue
                }
                rewardPresenter.show(.achievement(achievement))
                deliveryOutbox.mark(userId: userId, semanticId: semanticId, state: .presented)
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

        recheckServerRejectedUnlocks(user: user)
        self.previousSnapshot = snapshot
    }

    /// Re-sends unlock candidates the server could not verify yet.
    ///
    /// This service already refreshes on `userProgressionRepository.objectWillChange`, i.e. on every
    /// new server progression snapshot — and a new snapshot is precisely the state a rejected
    /// candidate was waiting for (the server evaluates `explorer_10` against its own
    /// `acceptedRegionFindCount`, which trails the local total that fired the popup). Rechecking
    /// here is what makes the XP and the cloud `user_achievements` row land in the same session
    /// instead of on the next cold start. Bounded by the sync service's recheck budget.
    private func recheckServerRejectedUnlocks(user: AppUser) {
        guard achievementUnlockSyncService.hasPendingCandidates else { return }
        let entitlement = entitlementService.entitlementState(for: user)
        Task {
            await achievementUnlockSyncService.retryPendingIfNeeded(user: user, entitlement: entitlement)
        }
    }

    private func establishBaseline(snapshot: AchievementProgressSnapshot, userId: String) {
        for (id, status) in snapshot.statuses where status.isUnlocked {
            try? userAchievementRepository.backfillIfMissing(
                userId: userId,
                achievementId: id,
                lastProgress: status.progress
            )
            deliveryOutbox.mark(userId: userId, semanticId: "ach-\(id)", state: .presented)
        }
        if snapshot.rankLevel > 1 {
            deliveryOutbox.mark(userId: userId, semanticId: "rank-\(snapshot.rankLevel)", state: .presented)
        }
        persistedAchievementIds = AchievementProgressPersistence.persistedAchievementIds(
            local: (try? userAchievementRepository.fetchRecords(forUserId: userId)) ?? [:],
            remote: userAchievementRemoteRepository.records
        )
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
        let userId = user.firebaseUID ?? user.id
        let events = (try? xpLedger.ledgerEvents(userId: userId)) ?? []
        let display = ProgressionDisplayTotalsResolver.resolve(
            userId: userId,
            ledgerEvents: events,
            serverSnapshot: userProgressionRepository.snapshot,
            verifiedGrantSum: nil,
            hasReceivedGrantSnapshot: false
        )
        // Prefer event-replay effective totals when they exceed ledger provisional (e.g. game_ended pending).
        if let effective = userProgressionService.effectiveTotals {
            return max(display.displayedTotalXp, effective.totalXp)
        }
        return display.displayedTotalXp
    }

    /// Offline-friendly: local effective progression is enough; remote achievement snapshot is optional.
    private func isHydrated(for user: AppUser) -> Bool {
        let hasLocalProgression = userProgressionService.effectiveTotals != nil
        let hasRemoteProgression = userProgressionRepository.hasReceivedInitialSnapshot
        guard hasLocalProgression || hasRemoteProgression else { return false }
        return isLifetimeStatsHydrated(for: user)
            || lifetimeStatsCoordinator.stats != nil
            || userAchievementRemoteRepository.hasReceivedInitialSnapshot
            || hasLocalProgression
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
