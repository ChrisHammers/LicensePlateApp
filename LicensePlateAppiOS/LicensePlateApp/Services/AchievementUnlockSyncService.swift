//
//  AchievementUnlockSyncService.swift
//  LicensePlateApp
//
//  Syncs client-computed unlock candidates to the server-authoritative store.
//

import FirebaseFunctions
import Foundation

struct AchievementUnlockSyncCandidate: Sendable {
    var achievementId: String
    var lastProgress: Int
}

struct AchievementUnlockSyncResult: Sendable {
    var recordedIds: [String]
    var alreadySyncedIds: [String]
    var rejectedIds: [String]
}

/// What one sync attempt cost. `heldForChildRestriction` is the FR-28 case: nothing was
/// delivered, but nothing was spent either — the batch waits for consent.
enum AchievementUnlockSyncAttempt: Equatable, Sendable {
    case succeeded
    case heldForChildRestriction
    case failed
}

@MainActor
final class AchievementUnlockSyncService {

    static let shared = AchievementUnlockSyncService()

    /// Performs the `syncUserAchievementUnlocks` call. Injectable so the FR-28 hold
    /// behaviour is testable without Firebase.
    private let remoteCall: ([String: Any]) async throws -> Any?
    /// FR-28: true while this session is a restricted unconsented child. Injectable.
    private var isRestrictedUnconsentedChild: () -> Bool
    private var pendingCandidates: [AchievementUnlockSyncCandidate] = []
    private var pendingUser: AppUser?
    private var pendingEntitlement: EntitlementState?
    private var pendingRetryCount = 0
    private let maxRetryAttempts = 3

    init(
        functions: Functions? = nil,
        remoteCall: (([String: Any]) async throws -> Any?)? = nil,
        isRestrictedUnconsentedChild: (() -> Bool)? = nil
    ) {
        self.remoteCall = remoteCall ?? { payload in
            try await AppCheckReadiness.ensureCallablePrerequisites()
            let fn = (functions ?? Functions.functions()).httpsCallable("syncUserAchievementUnlocks")
            return try await fn.call(payload).data
        }
        self.isRestrictedUnconsentedChild = isRestrictedUnconsentedChild
            ?? { ChildRestrictedModeService.shared.isRestrictedUnconsentedChild }
    }

    func configureRestrictionProvider(_ provider: @escaping () -> Bool) {
        isRestrictedUnconsentedChild = provider
    }

    @discardableResult
    func syncUnlocks(
        user: AppUser,
        entitlement: EntitlementState,
        candidates: [AchievementUnlockSyncCandidate]
    ) async -> AchievementUnlockSyncAttempt {
        guard !candidates.isEmpty else { return .succeeded }
        // FR-28 pre-emptive hold: the server would reject this anyway, and every rejection
        // used to spend one of three retries — so a child who unlocked achievements before
        // consent arrived with the budget gone and the batch discarded. Remember the
        // candidates, spend nothing, log nothing (FR-21: no child-only analytics on the
        // child's own instance).
        guard !isRestrictedUnconsentedChild() else {
            storePendingRetry(user: user, entitlement: entitlement, candidates: candidates)
            return .heldForChildRestriction
        }
        let payload: [String: Any] = [
            "candidates": candidates.map {
                [
                    "achievementId": $0.achievementId,
                    "lastProgress": $0.lastProgress
                ] as [String: Any]
            },
            "entitlementHints": entitlementHintsPayload(from: entitlement)
        ].addingClientMetadata()

        do {
            let data = try await remoteCall(payload)
            let parsed = parseSyncResponse(data)
            AnalyticsService.shared.log(
                .achievementUnlockSyncSucceeded(
                    recordedCount: parsed.recordedIds.count,
                    alreadySyncedCount: parsed.alreadySyncedIds.count,
                    rejectedCount: parsed.rejectedIds.count
                )
            )
            // Do not claw back local unlocks or show "removed" UI on rejectedIds.
            // Achievements stay unlocked locally unless removed from the backend.
            clearPendingRetryState()
            return .succeeded
        } catch {
            storePendingRetry(user: user, entitlement: entitlement, candidates: candidates)
            // A restriction rejection that raced the pre-emptive check is still a hold, not
            // a failure: keep the batch, spend nothing, stay silent (FR-21).
            guard !ChildRestrictedModeService.isChildRestrictionRejection(error) else {
                return .heldForChildRestriction
            }
            AnalyticsService.shared.log(
                .achievementUnlockSyncFailed(
                    candidateCount: candidates.count,
                    errorSummary: String(error.localizedDescription.prefix(120))
                )
            )
            #if DEBUG
            print("⚠️ syncUserAchievementUnlocks failed: \(error.localizedDescription)")
            #endif
            return .failed
        }
    }

    func syncUnlockedStatuses(
        user: AppUser,
        entitlement: EntitlementState,
        statuses: [String: AchievementStatus]
    ) async {
        let candidates = statuses.compactMap { id, status -> AchievementUnlockSyncCandidate? in
            guard status.isUnlocked else { return nil }
            return AchievementUnlockSyncCandidate(achievementId: id, lastProgress: status.progress)
        }
        await syncUnlocks(user: user, entitlement: entitlement, candidates: candidates)
    }

    func retryPendingIfNeeded(user: AppUser, entitlement: EntitlementState) async {
        guard !pendingCandidates.isEmpty else { return }
        guard pendingUser?.id == user.id || pendingUser?.firebaseUID == user.firebaseUID else { return }
        // FR-28: while restricted the call cannot succeed, so trying is pure cost. Hold the
        // batch and spend nothing — this is what keeps the budget intact until consent.
        guard !isRestrictedUnconsentedChild() else { return }
        guard pendingRetryCount < maxRetryAttempts else {
            AnalyticsService.shared.log(
                .achievementUnlockSyncFailed(
                    candidateCount: pendingCandidates.count,
                    errorSummary: "retry_limit_reached"
                )
            )
            clearPendingRetryState()
            return
        }
        pendingRetryCount += 1
        let attempt = await syncUnlocks(user: user, entitlement: entitlement, candidates: pendingCandidates)
        if attempt == .heldForChildRestriction {
            // The restriction landed between the guard above and the call. Refund: a policy
            // hold must never move the budget.
            pendingRetryCount = max(0, pendingRetryCount - 1)
        }
    }

    /// COPPA FR-28 consent resume: restores the full retry budget. A batch that survived
    /// the restricted period must not arrive at consent one failure from being discarded.
    func resetRetryBudgetAfterConsent() {
        pendingRetryCount = 0
    }

    /// Durable recovery (idempotent): re-sends locally-unlocked achievements as candidates,
    /// rather than just whatever survives in `pendingCandidates`.
    ///
    /// The in-memory pending batch is lost on app restart, so a child who unlocked
    /// achievements before consent and relaunched has nothing left to retry — the local
    /// `user_achievements` rows are the only durable record. The server dedupes by
    /// returning `alreadySyncedIds` and grants no XP for an already-recorded unlock, so
    /// re-sending is safe and repeatable.
    ///
    /// `candidates` must already respect the server's per-call cap; the caller
    /// (`ConsentRecoverySupport`) does the chunking.
    func resendAllLocallyUnlockedAchievements(
        user: AppUser,
        entitlement: EntitlementState,
        candidates: [AchievementUnlockSyncCandidate]
    ) async {
        guard !candidates.isEmpty else { return }
        await syncUnlocks(user: user, entitlement: entitlement, candidates: candidates)
    }

    func resetForSignOut() {
        clearPendingRetryState()
    }

    private func storePendingRetry(
        user: AppUser,
        entitlement: EntitlementState,
        candidates: [AchievementUnlockSyncCandidate]
    ) {
        pendingUser = user
        pendingEntitlement = entitlement
        var merged = Dictionary(uniqueKeysWithValues: pendingCandidates.map { ($0.achievementId, $0) })
        for candidate in candidates {
            merged[candidate.achievementId] = candidate
        }
        pendingCandidates = Array(merged.values)
    }

    private func clearPendingRetryState() {
        pendingCandidates = []
        pendingUser = nil
        pendingEntitlement = nil
        pendingRetryCount = 0
    }

    private func parseSyncResponse(_ data: Any?) -> AchievementUnlockSyncResult {
        guard let dict = data as? [String: Any] else {
            return AchievementUnlockSyncResult(recordedIds: [], alreadySyncedIds: [], rejectedIds: [])
        }
        return AchievementUnlockSyncResult(
            recordedIds: stringArray(dict["recordedIds"]),
            alreadySyncedIds: stringArray(dict["alreadySyncedIds"]),
            rejectedIds: stringArray(dict["rejectedIds"])
        )
    }

    private func stringArray(_ value: Any?) -> [String] {
        guard let array = value as? [Any] else { return [] }
        return array.compactMap { $0 as? String }
    }

    private func entitlementHintsPayload(from entitlement: EntitlementState) -> [String: Any] {
        [
            "isRoyale": entitlement.effectiveTier >= .royale
        ]
    }
}
