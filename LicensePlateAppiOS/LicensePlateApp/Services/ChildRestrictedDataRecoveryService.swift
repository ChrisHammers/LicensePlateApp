//
//  ChildRestrictedDataRecoveryService.swift
//  LicensePlateApp
//
//  COPPA FR-28, consent-resume durability. The restricted-child hold is only half a
//  contract: "local play continues, uploads resume at consent" is a promise that the
//  device still HAS the data when consent arrives. Two paths broke that promise, and
//  neither is recoverable by the ordinary retry machinery:
//
//  - A gameplay row that reached the `game not found` cap was cancelled outright, and
//    canonical replay re-uploads only `game_started` / `game_ended` / `game_completed`.
//    A cancelled `region_found` is a discovery that exists on the device and nowhere
//    else — the reported symptom (trips and games appear, the finds do not).
//  - The achievement batch lives in memory only, so an app restart during the restricted
//    period discards it with no durable trace to retry from.
//
//  This service is the durable second chance for both: it re-derives what should have
//  been uploaded from local persistence rather than from volatile retry state.
//
//  Three things keep it bounded, and all three matter:
//
//  1. **Child accounts only.** An adult never accumulated policy holds, so running any of
//     this for them would be pure cost — extra callables on every cold start.
//  2. **Never while restricted.** Running then would burn the very budgets the FR-28 holds
//     exist to preserve, and would make cloud calls for a child without consent.
//  3. **Self-quenching.** The gameplay pass settles every row it acts on, so the
//     recoverable set shrinks to empty instead of being rescanned forever. No device-side
//     one-shot flag is needed, and none is used.
//

import Foundation

@MainActor
final class ChildRestrictedDataRecoveryService {

    static let shared = ChildRestrictedDataRecoveryService()

    /// Injectable effects so the pass is testable without Firebase or singletons.
    struct Dependencies {
        /// FR-28: true while this session is a restricted unconsented child.
        var isRestrictedUnconsentedChild: () -> Bool
        /// True when this session is a child account at all (restricted or consented).
        var isChildAccountSession: () -> Bool
        /// True once this session's age/child status is resolved enough to act on.
        var isSessionResolved: () -> Bool
        /// Budget reset + cancelled-row re-enqueue + canonical publish + drain, all under
        /// the single-flush gate.
        var recoverAndDrainGameplay: () async -> Void
        /// Re-sends every locally-unlocked achievement as a sync candidate.
        var resendAllLocallyUnlockedAchievements: () async -> Void

        @MainActor
        static func live() -> Dependencies {
            Dependencies(
                isRestrictedUnconsentedChild: {
                    ChildRestrictedModeService.shared.isRestrictedUnconsentedChild
                },
                isChildAccountSession: {
                    ChildRestrictedModeService.shared.isChildAccountSession
                },
                isSessionResolved: { !ChildRestrictedModeService.shared.isAgeUnresolved },
                recoverAndDrainGameplay: {
                    await SyncCoordinator.shared.resumeGameplaySyncAfterChildConsent()
                },
                resendAllLocallyUnlockedAchievements: {
                    await ConsentRecoverySupport.resendAllLocallyUnlockedAchievements()
                }
            )
        }
    }

    private var deps: Dependencies
    /// In-memory only: one launch pass per process. Durable de-duplication is the row
    /// settling in `recoverDroppedGameplayEventRows`, not this flag.
    private var hasRunLaunchPass = false

    init(dependencies: Dependencies? = nil) {
        self.deps = dependencies ?? .live()
    }

    func configure(dependencies: Dependencies) {
        self.deps = dependencies
    }

    /// Hard sign-out: the next account gets its own launch pass.
    func resetForSignOut() {
        hasRunLaunchPass = false
    }

    /// Once per launch, for a resolved, unrestricted CHILD session. Catches the case
    /// consent resume cannot: the app was restarted after the restriction lifted, so no
    /// consent edge will ever fire again for data that was dropped before it.
    func runLaunchRecoveryIfEligible() async {
        guard !hasRunLaunchPass else { return }
        guard deps.isSessionResolved() else { return }
        guard deps.isChildAccountSession() else { return }
        guard !deps.isRestrictedUnconsentedChild() else { return }
        hasRunLaunchPass = true
        await run()
    }

    /// The consent edge. The caller has already established this is a child account whose
    /// restriction just lifted. Idempotent, so it composes safely with the launch pass.
    func runConsentRecovery() async {
        hasRunLaunchPass = true
        await run()
    }

    /// Gameplay first and achievements second, in both entry points: the achievement
    /// candidates are re-derived from progression that the gameplay drain is still
    /// settling, so re-sending before the drain would send a stale snapshot.
    private func run() async {
        await deps.recoverAndDrainGameplay()
        await deps.resendAllLocallyUnlockedAchievements()
    }
}

/// Whether a consent-edge kick is worth making at all.
///
/// The online check is the load-bearing part: these kicks spend REAL in-memory retry
/// budget (three attempts, then the batch is discarded), so firing them into a dead
/// network right after the consent edge would burn the batch for nothing. Skipping is
/// free — the pending state stays in memory and the next foreground retries.
enum ConsentRecoveryKickPolicy {
    static func shouldKick(userId: String, isOnline: Bool) -> Bool {
        !userId.isEmpty && isOnline
    }
}

/// Identity-bound consent effects. These need the signed-in user, entitlement, and local
/// rows, so `RootView` supplies ONLY the identity through `contextProvider` and every
/// repository read happens here in the service layer.
@MainActor
enum ConsentRecoverySupport {

    struct Context {
        var user: AppUser
        var userId: String
        var isOnline: Bool
    }

    static var contextProvider: () -> Context? = { nil }

    /// The server hard-rejects more than this many candidates per call
    /// (`syncUserAchievementUnlocks`: `invalid-argument`, "At most 20 achievement
    /// candidates are allowed"). The check is on the RAW array before the server dedupes,
    /// so chunking must count sent entries, not distinct ids.
    static let maxAchievementCandidatesPerCall = 20

    /// Re-sends every locally-unlocked achievement, in server-legal chunks.
    ///
    /// Online-guarded: a network drop right after the consent edge would otherwise spend
    /// real in-memory retry budget on calls that cannot succeed. Skipping is safe — the
    /// pending state persists and the next foreground retries.
    static func resendAllLocallyUnlockedAchievements() async {
        guard let context = contextProvider(),
              ConsentRecoveryKickPolicy.shouldKick(userId: context.userId, isOnline: context.isOnline) else { return }
        guard let records = try? UserAchievementRepository.shared.fetchRecords(forUserId: context.userId),
              !records.isEmpty else { return }
        let entitlement = EntitlementService.shared.entitlementState(for: context.user)
        // Stable order so chunk boundaries are deterministic run to run.
        let candidates = records.values
            .sorted { $0.achievementId < $1.achievementId }
            .map { AchievementUnlockSyncCandidate(achievementId: $0.achievementId, lastProgress: $0.lastProgress) }
        for chunk in stride(from: 0, to: candidates.count, by: maxAchievementCandidatesPerCall) {
            let batch = Array(candidates[chunk..<min(chunk + maxAchievementCandidatesPerCall, candidates.count)])
            await AchievementUnlockSyncService.shared.resendAllLocallyUnlockedAchievements(
                user: context.user,
                entitlement: entitlement,
                candidates: batch
            )
        }
    }

    /// Online-guarded for the same reason as the achievement resend.
    static func retryReturnStreakDailyClaim() async {
        guard let context = contextProvider(),
              ConsentRecoveryKickPolicy.shouldKick(userId: context.userId, isOnline: context.isOnline) else { return }
        await ReturnStreakDailyXpClaimService.shared.retryPendingIfNeeded(userId: context.userId)
    }

    static func reconcileXpGrants() async {
        guard let context = contextProvider(),
              ConsentRecoveryKickPolicy.shouldKick(userId: context.userId, isOnline: context.isOnline) else { return }
        _ = await XpGrantReconcileService.shared.reconcileIfNeeded(
            userId: context.userId,
            isOnline: context.isOnline
        )
    }
}
