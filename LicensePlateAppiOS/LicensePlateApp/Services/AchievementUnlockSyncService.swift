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

@MainActor
final class AchievementUnlockSyncService {

    static let shared = AchievementUnlockSyncService()

    private let functions: Functions
    private let userAchievementRepository: UserAchievementRepository
    private let deliveryOutbox: RewardDeliveryOutbox
    private var pendingCandidates: [AchievementUnlockSyncCandidate] = []
    private var pendingUser: AppUser?
    private var pendingEntitlement: EntitlementState?
    private var pendingRetryCount = 0
    private let maxRetryAttempts = 3

    init(
        functions: Functions = Functions.functions(),
        userAchievementRepository: UserAchievementRepository = .shared,
        deliveryOutbox: RewardDeliveryOutbox = .shared
    ) {
        self.functions = functions
        self.userAchievementRepository = userAchievementRepository
        self.deliveryOutbox = deliveryOutbox
    }

    func syncUnlocks(
        user: AppUser,
        entitlement: EntitlementState,
        candidates: [AchievementUnlockSyncCandidate]
    ) async {
        guard !candidates.isEmpty else { return }
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
            let fn = functions.httpsCallable("syncUserAchievementUnlocks")
            let result = try await fn.call(payload)
            let parsed = parseSyncResponse(result.data)
            AnalyticsService.shared.log(
                .achievementUnlockSyncSucceeded(
                    recordedCount: parsed.recordedIds.count,
                    alreadySyncedCount: parsed.alreadySyncedIds.count,
                    rejectedCount: parsed.rejectedIds.count
                )
            )
            applyRejectedIds(parsed.rejectedIds, user: user)
            // Keep only rejected/failed candidates for retry; clear accepted ones.
            let rejected = Set(parsed.rejectedIds)
            let remaining = candidates.filter { rejected.contains($0.achievementId) }
            if remaining.isEmpty {
                clearPendingRetryState()
            } else {
                storePendingRetry(user: user, entitlement: entitlement, candidates: remaining)
            }
        } catch {
            storePendingRetry(user: user, entitlement: entitlement, candidates: candidates)
            AnalyticsService.shared.log(
                .achievementUnlockSyncFailed(
                    candidateCount: candidates.count,
                    errorSummary: String(error.localizedDescription.prefix(120))
                )
            )
            #if DEBUG
            print("⚠️ syncUserAchievementUnlocks failed: \(error.localizedDescription)")
            #endif
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
        await syncUnlocks(user: user, entitlement: entitlement, candidates: pendingCandidates)
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

    private func applyRejectedIds(_ rejectedIds: [String], user: AppUser) {
        guard !rejectedIds.isEmpty else { return }
        let userId = user.firebaseUID ?? user.id
        let achievementsById = Dictionary(
            uniqueKeysWithValues: ProgressionCatalogProjection.achievements(
                from: ProgressionCatalogProvider.shared.current
            ).map { ($0.id, $0) }
        )
        for id in rejectedIds {
            try? userAchievementRepository.removeUnlock(userId: userId, achievementId: id)
            deliveryOutbox.mark(userId: userId, semanticId: "ach-\(id)", state: .clawedBack)
            let title = achievementsById[id]?.title ?? id
            RewardPresenter.shared.show(
                .unlock(
                    title: "reward.popup.achievement_removed.title".localized,
                    detail: "reward.popup.achievement_removed.detail".localized(title),
                    icon: "xmark.circle.fill",
                    rarity: .common
                )
            )
        }
    }
}
