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

@MainActor
final class AchievementUnlockSyncService {

    static let shared = AchievementUnlockSyncService()

    private let functions: Functions

    init(functions: Functions = Functions.functions()) {
        self.functions = functions
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
            _ = try await fn.call(payload)
        } catch {
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

    private func entitlementHintsPayload(from entitlement: EntitlementState) -> [String: Any] {
        [
            "isRoyale": entitlement.effectiveTier >= .royale,
            "isFounder": entitlement.hasTag("founder")
        ]
    }
}
