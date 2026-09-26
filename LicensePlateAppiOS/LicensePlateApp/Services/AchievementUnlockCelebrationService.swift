//
//  AchievementUnlockCelebrationService.swift
//  LicensePlateApp
//
//  Observes progression snapshots and queues rank/achievement celebration popups.
//  Offline-capable: baselines historical state at attach, then celebrates in-session transitions.
//
//  §3.1.1 item 15 (2026-09-18): "historical state at attach" has two halves, both kept by
//  `AchievementCelebrationBaselineTracker` (read its header). This file owns the side effects:
//  absorbed remote history is backfilled and marked delivered exactly like the local baseline, so
//  the suppression also survives a relaunch. `hasReceivedInitialSnapshot` still only feeds
//  `isHydrated` — it means "a callback happened", never "the server answered".
//

import Combine
import Foundation

/// The "already shown in THIS process" ledger of celebration semantic ids — no IDENTITY change can
/// clear it (§3.1.1 item 15). Sibling of `XpGainToastService.presentedLedgerRowIds`.
///
/// The one exception is an account PURGE, which is not an identity change but a statement that this
/// device's history is gone: `LocalUserDataPurgeService` deletes the local achievement rows and the
/// uid's outbox marks for exactly that reason, and a ledger that outlived them would silence an
/// achievement the player then re-earns in the same process (2026-09-19). `clearForAccountPurge` is
/// reachable only from that path — never from `configure(user:)` or `resetForSignOut`, which
/// `RootView` runs on every uid change including an identity rebind.
struct CelebrationProcessPresentationLedger {

    private var presentedSemanticIds: Set<String> = []

    /// True the first time this process claims `semanticId`, false every time after.
    mutating func claim(_ semanticId: String) -> Bool {
        presentedSemanticIds.insert(semanticId).inserted
    }

    /// Hard purge ONLY. See the type's note.
    mutating func clearForAccountPurge() {
        presentedSemanticIds.removeAll()
    }

    var presentedCount: Int { presentedSemanticIds.count }
}

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
    private var tracker = AchievementCelebrationBaselineTracker()
    private var persistedAchievementIds: Set<String> = []
    /// PROCESS-lifetime, deliberately NOT cleared by `configure(user:)` or `resetForSignOut`: the
    /// semantic ids (`rank-<level>` / `ach-<id>`) this process has already shown. `configure` starts
    /// a new identity epoch and drops the baseline, and the delivery outbox is keyed by uid — so
    /// without this, a mid-session identity change (FR-60 provision-at-consent, guest → registered
    /// link, FR-84 transfer) re-shows the popup the user watched seconds earlier, from the new
    /// uid's empty outbox. `RewardDeliveryOutbox.rebind(from:to:)` carries the marks across that
    /// same boundary; this is the in-process backstop for the window where a mark exists on
    /// neither side (the popup is on screen, nothing acknowledged yet).
    /// Precedent and shape: `XpGainToastService.presentedLedgerRowIds`.
    /// ACCEPTED COST: a DIFFERENT account signing in inside this same process would not re-see an
    /// id this process already showed. That is one celebration in one session, never a permanent
    /// mute — the outbox is per-uid, so the next launch decides on that account's own marks.
    /// The one case that cost was NOT meant to cover is an account purge, which also deletes the
    /// local rows and the outbox marks: `resetProcessPresentationsForAccountPurge()` clears it
    /// there, and only there.
    private var processPresentations = CelebrationProcessPresentationLedger()

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
        tracker.reset()
        persistedAchievementIds = []
        userAchievementRemoteRepository.stopListening()
        guard let user else { return }
        let userId = user.firebaseUID ?? user.id
        CelebrationDiagnostics.log(
            "configure uid=\(CelebrationDiagnostics.shortUid(userId)) progUid=\(CelebrationDiagnostics.shortUid(userProgressionRepository.boundUserId)) progGen=\(userProgressionRepository.bindingGeneration) progSealed=\(userProgressionRepository.hasReceivedServerSnapshot ? 1 : 0)"
        )
        lifetimeStatsCoordinator.onProfileAppear(userId: userId)
        userAchievementRemoteRepository.startListening(userId: userId)
        reloadPersistedAchievementIds(for: userId)
        scheduleRefresh()
    }

    func resetForSignOut() {
        refreshWorkItem?.cancel()
        refreshWorkItem = nil
        user = nil
        tracker.reset()
        persistedAchievementIds = []
        userAchievementRemoteRepository.stopListening()
        achievementUnlockSyncService.resetForSignOut()
        rewardPresenter.reset()
        XpClawbackPresentationService.shared.resetForSignOut()
    }

    /// ONLY for a genuine account purge (hard sign-out to a fresh guest, delete account), from
    /// `LocalUserDataPurgeService` — never from `resetForSignOut`, which `RootView` also calls on
    /// every uid change, and never from `configure(user:)`. The purge deletes this device's local
    /// achievement rows and the uid's outbox marks; keeping the process ledger past that point
    /// would mute a re-earned id for the rest of the process (§3.1.1 item 15, 2026-09-19).
    func resetProcessPresentationsForAccountPurge() {
        CelebrationDiagnostics.log("presented.reset count=\(processPresentations.presentedCount) reason=account_purge")
        processPresentations.clearForAccountPurge()
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

        guard let step = tracker.ingest(
            snapshot: snapshot,
            isHydrated: isHydrated(for: user),
            remote: remoteWatermark(userId: userId),
            serverBackedSnapshot: { self.serverBackedSnapshot(user: user, userId: userId) }
        ) else {
            return
        }

        if let baseline = step.localBaseline {
            establishBaseline(snapshot: baseline, userId: userId)
            CelebrationDiagnostics.log(
                "baseline.local rank=\(baseline.rankLevel) totalXp=\(baseline.totalXp) unlocked=\(baseline.statuses.values.filter(\.isUnlocked).count)"
            )
        }
        if let absorption = step.remoteAbsorption {
            absorbRemoteHistory(absorption, user: user, userId: userId)
        }

        let catalog = catalogProvider.current
        let ladder = ProgressionCatalogProjection.rankLadder(from: catalog)
        let achievementsById = Dictionary(uniqueKeysWithValues: ProgressionCatalogProjection.achievements(from: catalog).map { ($0.id, $0) })

        if catalog.presentation.rankProgressionEnabled,
           let newLevel = step.rankUpLevel,
           let rank = ladder.ranks.first(where: { $0.level == newLevel }) {
            let semanticId = "rank-\(newLevel)"
            // Unlike the achievement branch, a rank-up has no bookkeeping beyond the presentation
            // itself (no local row, no cloud sync), so the ledger may guard the whole block.
            if !deliveryOutbox.hasPresentedOrDismissed(userId: userId, semanticId: semanticId),
               claimPresentation(semanticId: semanticId) {
                CelebrationDiagnostics.log("present rank=\(newLevel) totalXp=\(snapshot.totalXp)")
                rewardPresenter.show(.rankUp(rank))
                deliveryOutbox.mark(userId: userId, semanticId: semanticId, state: .presented)
                AnalyticsService.shared.log(
                    .rankUpCelebrated(level: newLevel, totalXp: snapshot.totalXp)
                )
            }
        }

        if catalog.presentation.achievementsEnabled {
            let unlockedIds = step.newlyUnlockedIds
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
                // The process ledger withholds the PRESENTATION only (§3.1.1 item 15, 2026-09-19).
                // The unlock itself is not a celebration: recording it locally, marking it persisted
                // and pushing it to the cloud must happen whether or not this process already showed
                // the popup, or a mid-session identity change would cost the player the unlock row
                // and its cloud sync — "nothing is withheld". A ledger skip deliberately does NOT
                // mark the outbox, so the next launch still decides on this account's own marks.
                if claimPresentation(semanticId: semanticId) {
                    CelebrationDiagnostics.log("present ach=\(id)")
                    rewardPresenter.show(.achievement(achievement))
                    deliveryOutbox.mark(userId: userId, semanticId: semanticId, state: .presented)
                    AnalyticsService.shared.log(
                        .achievementUnlocked(
                            achievementId: id,
                            category: achievement.category.rawValue,
                            rarity: achievement.rarity.title
                        )
                    )
                }
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
    }

    // MARK: - Never twice in one process (§3.1.1 item 15)

    /// Insert-and-test on `processPresentations`, called immediately before every
    /// `rewardPresenter.show` for a rank or an achievement. Returns false when this process has
    /// already shown that semantic id; the caller then skips the presentation entirely (it does not
    /// mark the outbox — the suppression is deliberately in-process only, so the next launch still
    /// decides on this account's own marks).
    private func claimPresentation(semanticId: String) -> Bool {
        guard processPresentations.claim(semanticId) else {
            CelebrationDiagnostics.log("presented.skip id=\(semanticId) reason=process_presented_set")
            return false
        }
        return true
    }

    // MARK: - Remote history (§3.1.1 item 15)

    /// Fails closed: a listener that is stopped, or bound to another identity, offers no key — so
    /// nothing of it is absorbed and nothing seals.
    ///
    /// The key is keyed on `identityEpoch`, NOT `bindingGeneration` (§3.1.1 item 15, 2026-09-19).
    /// Both repositories bump `bindingGeneration` inside `attachListener`, which the listen-error
    /// rebind also runs — keying the seal on it re-opened the absorb window on every transient
    /// listen failure, so the first post-rebind server gain (a peer-awarded placement crossing a
    /// rank) was swallowed as history and durably marked presented. `identityEpoch` moves only on a
    /// real (re)bind or a stop, which is exactly when the history line has to be redrawn.
    ///
    /// `isServerConfirmed` waits on every server-backed input `serverBackedSnapshot` reads that can
    /// answer: both listeners AND the public lifetime stats profile listener (`plates_*` /
    /// `trips_*` hydrate from it and would otherwise present as fresh unlocks on a reinstall).
    /// RESIDUAL, deliberately not invented here: the entitlement / family flags
    /// (`royale_member`, `founder`, `family_member`) have no "resolved" signal on
    /// `EntitlementService`, so they can still hydrate after the seal.
    private func remoteWatermark(userId: String) -> AchievementCelebrationBaselineTracker.RemoteWatermark {
        guard userProgressionRepository.boundUserId == userId,
              userAchievementRemoteRepository.boundUserId == userId else {
            return .init(bindingKey: nil, isServerConfirmed: false)
        }
        return .init(
            bindingKey: "\(userId)#\(userProgressionRepository.identityEpoch)#\(userAchievementRemoteRepository.identityEpoch)",
            isServerConfirmed: userProgressionRepository.hasReceivedServerSnapshot
                && userAchievementRemoteRepository.hasReceivedServerSnapshot
                && publicLifetimeStatsRepository.hasReceivedInitialProfileSnapshot(forUserId: userId)
        )
    }

    /// What the server-backed state ALONE shows: the progression document read straight from the
    /// repository (not through `effectiveTotals`, which trails it by a debounce and adds local
    /// pending), server lifetime stats, remote records — no ledger, no pending events. Family and
    /// entitlement flags are the same as the full snapshot's: neither can change offline, so while
    /// unsealed they are history too.
    ///
    /// Four server-backed inputs, and the seal waits on three of them (`remoteWatermark`): the
    /// progression listener, the achievements listener and the public lifetime stats profile
    /// snapshot. The fourth — the entitlement / family flags — has no "resolved" signal to wait
    /// on, so `royale_member` / `founder` / `family_member` can still hydrate after the seal and
    /// present as fresh unlocks when the remote `user_achievements` row is missing (open,
    /// 2026-09-19).
    private func serverBackedSnapshot(user: AppUser, userId: String) -> AchievementProgressSnapshot {
        let server = userProgressionRepository.snapshot
        let entitlement = entitlementService.entitlementState(for: user)
        let serverStats = publicLifetimeStatsRepository.snapshot(forUserId: userId)
            ?? (try? publicLifetimeStatsRepository.cachedStatsFromDisk(forUserId: userId))
        let inputs = AchievementProgressInputs(
            progression: server.map { UserProgressionEffectiveTotals.combined(server: $0, pending: .zero) },
            lifetimeStats: serverStats,
            isFamilyMember: user.activeFamilyId != nil || user.wasEverInFamily,
            isRoyale: entitlement.effectiveTier >= .royale,
            isFounder: entitlement.hasTag("founder")
        )
        return AchievementProgressSnapshotBuilder.build(
            user: user,
            lifetimeStats: serverStats,
            totalXp: server?.totalXp ?? 0,
            catalogProvider: catalogProvider,
            userProgressionService: userProgressionService,
            entitlementService: entitlementService,
            inputs: inputs,
            remotePersistedRecords: userAchievementRemoteRepository.records
        )
    }

    /// Same bookkeeping as `establishBaseline`, for history that arrived after it. The trace carries
    /// the counterfactual: what the pre-item-15 build would have queued from this snapshot.
    private func absorbRemoteHistory(
        _ absorption: AchievementCelebrationBaselineTracker.RemoteAbsorption,
        user: AppUser,
        userId: String
    ) {
        // The counterfactual is DEBUG-only: only the trace consumes it, and
        // `CelebrationDiagnostics.log` compiles to nothing in release.
        #if DEBUG
        var exposedIds: [String] = []
        var exposedRank: Int?
        #endif
        for id in absorption.newlyAbsorbedIds {
            guard let status = absorption.history.statuses[id] else { continue }
            let semanticId = "ach-\(id)"
            let alreadyDelivered = deliveryOutbox.hasPresentedOrDismissed(userId: userId, semanticId: semanticId)
            #if DEBUG
            if !alreadyDelivered, !persistedAchievementIds.contains(id) {
                exposedIds.append(id)
            }
            #endif
            _ = try? userAchievementRepository.backfillIfMissing(
                userId: userId,
                achievementId: id,
                lastProgress: status.progress
            )
            if !alreadyDelivered {
                deliveryOutbox.mark(userId: userId, semanticId: semanticId, state: .presented)
            }
        }
        if let level = absorption.newlyAbsorbedRankLevel {
            let semanticId = "rank-\(level)"
            if !deliveryOutbox.hasPresentedOrDismissed(userId: userId, semanticId: semanticId) {
                #if DEBUG
                exposedRank = level
                #endif
                deliveryOutbox.mark(userId: userId, semanticId: semanticId, state: .presented)
            }
        }
        if !absorption.newlyAbsorbedIds.isEmpty {
            reloadPersistedAchievementIds(for: userId)
        }
        #if DEBUG
        CelebrationDiagnostics.log(
            "remote.\(absorption.sealed ? "seal" : "absorb") rank=\(absorption.history.rankLevel) totalXp=\(absorption.history.totalXp) newIds=\(absorption.newlyAbsorbedIds.count) newRank=\(absorption.newlyAbsorbedRankLevel.map(String.init) ?? "-") [PRE-FIX exposure: rankBanner=\(exposedRank.map(String.init) ?? "-") popups=\(exposedIds.count)\(exposedIds.isEmpty ? "" : " " + exposedIds.joined(separator: ","))]"
        )
        #endif

        guard absorption.sealed else { return }
        // The records are server-confirmed now, so "unlocked here, no record there" is knowable:
        // push those like the local baseline pushes its own. Empty on a healthy account.
        let unrecorded = absorption.history.statuses.filter { id, status in
            status.isUnlocked && userAchievementRemoteRepository.records[id] == nil
        }
        guard !unrecorded.isEmpty else { return }
        let entitlement = entitlementService.entitlementState(for: user)
        Task {
            await achievementUnlockSyncService.syncUnlockedStatuses(
                user: user,
                entitlement: entitlement,
                statuses: unrecorded
            )
        }
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
