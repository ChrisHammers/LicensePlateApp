//
//  ProgressionXpDriftAfterSyncReporter.swift
//  LicensePlateApp
//
//  After an online gameplay sync drain empties the queue, wait for the progression
//  Firestore trigger (or a settle timeout), then emit searchable analytics if XP
//  is still mismatched (open provisional / pending local / grant ledger).
//

import Foundation

/// Snapshot of XP integrity signals used for post-sync drift detection.
struct ProgressionXpDriftSnapshot: Equatable, Sendable {
    var openProvisionalXp: Int
    var hasPendingLocalProgression: Bool
    var pendingLocalXpDelta: Int
    var serverTotalXp: Int
    var verifiedGrantSum: Int?
    var hasReceivedGrantSnapshot: Bool
    var grantLedgerMismatch: Bool

    var hasOpenProvisional: Bool { openProvisionalXp > 0 }

    var hasAnyDrift: Bool {
        hasOpenProvisional || hasPendingLocalProgression || grantLedgerMismatch
    }

    /// Coarse fingerprint for rate-limiting repeat telemetry of the same sticky state.
    var signature: String {
        let verified = verifiedGrantSum.map(String.init) ?? "nil"
        return [
            String(openProvisionalXp),
            hasPendingLocalProgression ? "1" : "0",
            String(pendingLocalXpDelta),
            String(serverTotalXp),
            verified,
            grantLedgerMismatch ? "1" : "0"
        ].joined(separator: "|")
    }
}

enum ProgressionXpDriftEvaluator {
    static func snapshot(
        ledgerEvents: [XpLedgerEvent],
        serverSnapshot: UserProgressionSnapshot?,
        effectiveTotals: UserProgressionEffectiveTotals?,
        verifiedGrantSum: Int?,
        hasReceivedGrantSnapshot: Bool
    ) -> ProgressionXpDriftSnapshot {
        let serverXp = max(0, serverSnapshot?.totalXp ?? 0)
        let display = ProgressionDisplayTotalsResolver.resolve(
            userId: "",
            ledgerEvents: ledgerEvents,
            serverSnapshot: serverSnapshot,
            verifiedGrantSum: verifiedGrantSum,
            hasReceivedGrantSnapshot: hasReceivedGrantSnapshot
        )
        let pendingLocal = effectiveTotals?.hasPendingLocalProgression == true
        let pendingDelta: Int = {
            guard let effectiveTotals else { return 0 }
            return effectiveTotals.totalXp - serverXp
        }()
        let grantMismatch = hasReceivedGrantSnapshot
            && verifiedGrantSum != nil
            && verifiedGrantSum != serverXp
        return ProgressionXpDriftSnapshot(
            openProvisionalXp: display.openProvisionalXp,
            hasPendingLocalProgression: pendingLocal,
            pendingLocalXpDelta: pendingDelta,
            serverTotalXp: serverXp,
            verifiedGrantSum: hasReceivedGrantSnapshot ? verifiedGrantSum : nil,
            hasReceivedGrantSnapshot: hasReceivedGrantSnapshot,
            grantLedgerMismatch: grantMismatch
        )
    }
}

@MainActor
final class ProgressionXpDriftAfterSyncReporter {

    static let shared = ProgressionXpDriftAfterSyncReporter()

    /// Max wait for `onActivityEventUpdateUserProgression` to land in the progression listener.
    static let settleTimeoutNanoseconds: UInt64 = 45_000_000_000

    /// Poll interval while waiting for applied progression event ids.
    static let settlePollNanoseconds: UInt64 = 500_000_000

    /// Avoid flooding Analytics when sticky drift is re-checked every foreground/reachability flush.
    static let minRepeatInterval: TimeInterval = 3_600

    private var settleTask: Task<Void, Never>?
    private var lastLoggedSignature: String?
    private var lastLoggedAt: Date?
    private var analytics: AnalyticsLogging

    init(analytics: AnalyticsLogging = AnalyticsService.shared) {
        self.analytics = analytics
    }

    func resetForSignOut() {
        settleTask?.cancel()
        settleTask = nil
        lastLoggedSignature = nil
        lastLoggedAt = nil
    }

    /// Call when gameplay sync finished online with an empty pending/retry-due gameplay queue.
    /// - Parameter recentlyAcceptedProgressionSourceEventIds: `region_found` / `game_ended` event ids
    ///   accepted in this drain; used to wait for the progression Cloud Function trigger when possible.
    func scheduleEvaluationAfterSuccessfulGameplayDrain(
        recentlyAcceptedProgressionSourceEventIds: Set<String>,
        isOnline: @escaping () -> Bool = { true },
        hasPendingOrRetryDueGameplay: @escaping () -> Bool = { false }
    ) {
        settleTask?.cancel()
        let acceptedIds = recentlyAcceptedProgressionSourceEventIds
        settleTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let startedAt = Date()
            let confirmed = await self.waitForProgressionSettle(
                recentlyAcceptedProgressionSourceEventIds: acceptedIds,
                isOnline: isOnline,
                hasPendingOrRetryDueGameplay: hasPendingOrRetryDueGameplay
            )
            guard !Task.isCancelled else { return }
            guard isOnline() else { return }
            guard !hasPendingOrRetryDueGameplay() else { return }

            // Allow UserProgressionService’s short debounce after a late snapshot tick.
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            guard isOnline(), !hasPendingOrRetryDueGameplay() else { return }

            let settleWaitMs = Int(Date().timeIntervalSince(startedAt) * 1_000)
            self.evaluateAndLogIfNeeded(
                recentlyAcceptedCount: acceptedIds.count,
                progressionTriggerConfirmed: confirmed,
                settleWaitMs: settleWaitMs
            )
        }
    }

    /// Returns `true` when every recently accepted event id appears in `appliedProgressionEventIds`.
    /// When nothing was accepted this drain (sticky offline repair path), waits the full settle window and returns `false`.
    private func waitForProgressionSettle(
        recentlyAcceptedProgressionSourceEventIds: Set<String>,
        isOnline: () -> Bool,
        hasPendingOrRetryDueGameplay: () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(Int64(Self.settleTimeoutNanoseconds / 1_000_000_000))
        let waitingForTrigger = !recentlyAcceptedProgressionSourceEventIds.isEmpty

        while ContinuousClock.now < deadline {
            if Task.isCancelled { return false }
            guard isOnline() else { return false }
            guard !hasPendingOrRetryDueGameplay() else { return false }

            if waitingForTrigger {
                let applied = UserProgressionRepository.shared.snapshot?.appliedProgressionEventIds ?? []
                if recentlyAcceptedProgressionSourceEventIds.isSubset(of: applied) {
                    return true
                }
            }

            try? await Task.sleep(nanoseconds: Self.settlePollNanoseconds)
        }

        guard waitingForTrigger else { return false }
        let applied = UserProgressionRepository.shared.snapshot?.appliedProgressionEventIds ?? []
        return recentlyAcceptedProgressionSourceEventIds.isSubset(of: applied)
    }

    private func evaluateAndLogIfNeeded(
        recentlyAcceptedCount: Int,
        progressionTriggerConfirmed: Bool,
        settleWaitMs: Int
    ) {
        guard UserProgressionRepository.shared.hasReceivedInitialSnapshot else { return }
        guard let uid = UserProgressionRepository.shared.currentObservedUserId, !uid.isEmpty else { return }

        let ledgerEvents = (try? XpLedgerRepository.shared.ledgerEvents(userId: uid)) ?? []
        let grantRepo = XpGrantRemoteRepository.shared
        let hasGrantSnapshot = grantRepo.hasReceivedInitialSnapshot
        let verified: Int? = hasGrantSnapshot ? grantRepo.verifiedTotalXp : nil

        let drift = ProgressionXpDriftEvaluator.snapshot(
            ledgerEvents: ledgerEvents,
            serverSnapshot: UserProgressionRepository.shared.snapshot,
            effectiveTotals: UserProgressionService.shared.effectiveTotals,
            verifiedGrantSum: verified,
            hasReceivedGrantSnapshot: hasGrantSnapshot
        )
        guard drift.hasAnyDrift else { return }

        let now = Date()
        if let lastLoggedAt,
           let lastLoggedSignature,
           lastLoggedSignature == drift.signature,
           now.timeIntervalSince(lastLoggedAt) < Self.minRepeatInterval {
            return
        }

        analytics.log(
            .progressionXpDriftAfterSync(
                openProvisionalXp: drift.openProvisionalXp,
                hasOpenProvisional: drift.hasOpenProvisional,
                hasPendingLocalProgression: drift.hasPendingLocalProgression,
                pendingLocalXpDelta: drift.pendingLocalXpDelta,
                serverTotalXp: drift.serverTotalXp,
                verifiedGrantSum: drift.verifiedGrantSum,
                grantLedgerMismatch: drift.grantLedgerMismatch,
                hasReceivedGrantSnapshot: drift.hasReceivedGrantSnapshot,
                progressionTriggerConfirmed: progressionTriggerConfirmed,
                recentlyAcceptedCount: recentlyAcceptedCount,
                settleWaitMs: settleWaitMs
            )
        )
        lastLoggedSignature = drift.signature
        lastLoggedAt = now
    }
}
