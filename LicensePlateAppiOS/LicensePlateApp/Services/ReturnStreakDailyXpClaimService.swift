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

    /// Performs the `claimReturnStreakDailyXp` call. Injectable so the FR-28 hold
    /// behaviour is testable without Firebase.
    private let remoteCall: ([String: Any]) async throws -> Any?
    /// FR-28: true while this session is a restricted unconsented child. Injectable.
    private var isRestrictedUnconsentedChild: () -> Bool
    private var pendingCandidate: ReturnStreakDailyXpClaimCandidate?
    private var pendingUserId: String?
    private var pendingRetryCount = 0
    private let maxRetryAttempts = 3

    init(
        functions: Functions? = nil,
        remoteCall: (([String: Any]) async throws -> Any?)? = nil,
        isRestrictedUnconsentedChild: (() -> Bool)? = nil
    ) {
        self.remoteCall = remoteCall ?? { payload in
            try await AppCheckReadiness.ensureCallablePrerequisites()
            let fn = (functions ?? Functions.functions()).httpsCallable("claimReturnStreakDailyXp")
            return try await fn.call(payload).data
        }
        self.isRestrictedUnconsentedChild = isRestrictedUnconsentedChild
            ?? { ChildRestrictedModeService.shared.isRestrictedUnconsentedChild }
    }

    func configureRestrictionProvider(_ provider: @escaping () -> Bool) {
        isRestrictedUnconsentedChild = provider
    }

    func claimIfNeeded(userId: String, dayKey: String, currentStreak: Int) async {
        guard !userId.isEmpty, !dayKey.isEmpty, currentStreak >= 2 else { return }
        let candidate = ReturnStreakDailyXpClaimCandidate(dayKey: dayKey, currentStreak: currentStreak)
        await claim(userId: userId, candidate: candidate)
    }

    func retryPendingIfNeeded(userId: String) async {
        guard let pending = pendingCandidate else { return }
        guard pendingUserId == userId else { return }
        // FR-28: while restricted the claim cannot succeed, so trying is pure cost. Hold
        // the day's candidate and spend nothing.
        guard !isRestrictedUnconsentedChild() else { return }
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
        let didHold = await claim(userId: userId, candidate: pending)
        if didHold {
            // Restriction landed between the guard and the call — refund, a policy hold
            // must never move the budget.
            pendingRetryCount = max(0, pendingRetryCount - 1)
        }
    }

    /// COPPA FR-28 consent resume: restores the full retry budget so a claim that waited
    /// out the restricted period is not one failure from being discarded.
    func resetRetryBudgetAfterConsent() {
        pendingRetryCount = 0
    }

    func resetForSignOut() {
        clearPendingRetryState()
    }

    // MARK: - Private

    /// Returns `true` when the attempt was an FR-28 hold (nothing delivered, nothing spent).
    @discardableResult
    private func claim(userId: String, candidate: ReturnStreakDailyXpClaimCandidate) async -> Bool {
        // FR-28 pre-emptive hold: the server rejects unconsented children, and that
        // rejection used to burn one of three retries and then discard the day. Remember
        // the day, spend nothing, log nothing (FR-21: no child-only analytics on the
        // child's own instance).
        guard !isRestrictedUnconsentedChild() else {
            storePendingRetry(userId: userId, candidate: candidate)
            return true
        }
        let payload: [String: Any] = [
            "dayKey": candidate.dayKey,
            "currentStreak": candidate.currentStreak,
        ].addingClientMetadata()

        do {
            let data = try await remoteCall(payload)
            let parsed = parseResponse(data)
            AnalyticsService.shared.log(
                .returnStreakDailyXpClaimSucceeded(
                    dayKey: candidate.dayKey,
                    currentStreak: candidate.currentStreak,
                    granted: parsed.granted,
                    alreadyClaimed: parsed.alreadyClaimed
                )
            )
            clearPendingRetryState()
            return false
        } catch {
            storePendingRetry(userId: userId, candidate: candidate)
            // A restriction rejection that raced the pre-emptive check is still a hold:
            // keep the day, spend nothing, stay silent (FR-21).
            guard !ChildRestrictedModeService.isChildRestrictionRejection(error) else {
                return true
            }
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
            return false
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
