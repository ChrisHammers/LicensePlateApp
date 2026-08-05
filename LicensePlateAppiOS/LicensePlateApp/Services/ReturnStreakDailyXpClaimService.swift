//
//  ReturnStreakDailyXpClaimService.swift
//  LicensePlateApp
//
//  Claims server-authoritative return-streak daily XP after a local qualifying day (streak >= 2).
//

import FirebaseFunctions
import Foundation

struct ReturnStreakDailyXpClaimCandidate: Equatable, Sendable {
    var dayKey: String
    var currentStreak: Int
}

@MainActor
final class ReturnStreakDailyXpClaimService {

    static let shared = ReturnStreakDailyXpClaimService()

    private let functions: Functions
    private var pendingCandidate: ReturnStreakDailyXpClaimCandidate?
    private var pendingUserId: String?
    private var pendingRetryCount = 0
    private let maxRetryAttempts = 3

    init(functions: Functions = Functions.functions()) {
        self.functions = functions
    }

    func claimIfNeeded(userId: String, dayKey: String, currentStreak: Int) async {
        guard !userId.isEmpty, !dayKey.isEmpty, currentStreak >= 2 else { return }
        let candidate = ReturnStreakDailyXpClaimCandidate(dayKey: dayKey, currentStreak: currentStreak)
        await claim(userId: userId, candidate: candidate)
    }

    func retryPendingIfNeeded(userId: String) async {
        guard let pending = pendingCandidate else { return }
        guard pendingUserId == userId else { return }
        guard pendingRetryCount < maxRetryAttempts else {
            AnalyticsService.shared.log(
                .returnStreakDailyXpClaimFailed(
                    dayKey: pending.dayKey,
                    currentStreak: pending.currentStreak,
                    errorSummary: "retry_limit_reached"
                )
            )
            clearPendingRetryState()
            return
        }
        pendingRetryCount += 1
        await claim(userId: userId, candidate: pending)
    }

    func resetForSignOut() {
        clearPendingRetryState()
    }

    // MARK: - Private

    private func claim(userId: String, candidate: ReturnStreakDailyXpClaimCandidate) async {
        let payload: [String: Any] = [
            "dayKey": candidate.dayKey,
            "currentStreak": candidate.currentStreak,
        ].addingClientMetadata()

        do {
            try await AppCheckReadiness.ensureCallablePrerequisites()
            let fn = functions.httpsCallable("claimReturnStreakDailyXp")
            let result = try await fn.call(payload)
            let parsed = parseResponse(result.data)
            AnalyticsService.shared.log(
                .returnStreakDailyXpClaimSucceeded(
                    dayKey: candidate.dayKey,
                    currentStreak: candidate.currentStreak,
                    granted: parsed.granted,
                    alreadyClaimed: parsed.alreadyClaimed
                )
            )
            clearPendingRetryState()
        } catch {
            storePendingRetry(userId: userId, candidate: candidate)
            AnalyticsService.shared.log(
                .returnStreakDailyXpClaimFailed(
                    dayKey: candidate.dayKey,
                    currentStreak: candidate.currentStreak,
                    errorSummary: String(error.localizedDescription.prefix(120))
                )
            )
            #if DEBUG
            print("⚠️ claimReturnStreakDailyXp failed: \(error.localizedDescription)")
            #endif
        }
    }

    private func storePendingRetry(userId: String, candidate: ReturnStreakDailyXpClaimCandidate) {
        pendingUserId = userId
        pendingCandidate = candidate
    }

    private func clearPendingRetryState() {
        pendingCandidate = nil
        pendingUserId = nil
        pendingRetryCount = 0
    }

    private struct ClaimResponse {
        var granted: Bool
        var alreadyClaimed: Bool
    }

    private func parseResponse(_ data: Any?) -> ClaimResponse {
        guard let dict = data as? [String: Any] else {
            return ClaimResponse(granted: false, alreadyClaimed: false)
        }
        return ClaimResponse(
            granted: dict["granted"] as? Bool ?? false,
            alreadyClaimed: dict["alreadyClaimed"] as? Bool ?? false
        )
    }
}
