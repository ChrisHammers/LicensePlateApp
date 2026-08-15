//
//  AchievementUnlockServerCatchUpTests.swift
//  LicensePlateAppTests
//
//  Owner device testing 2026-08-15: "Getting Started" (`explorer_10`) fired its popup, granted no
//  XP, never appeared in cloud `user_achievements`, and only landed after an app restart — while
//  "Family Road Trip" worked every time.
//
//  Mechanism: the client unlocks from LOCAL progression the moment the 10th find commits, but
//  `syncUserAchievementUnlocks` re-evaluates every candidate against the server's own
//  `user_progression.acceptedRegionFindCount`, which trails until the gameplay event reaches
//  `onActivityEventUpdateUserProgression`. The candidate therefore comes back in `rejectedIds` —
//  and the client used to treat that as a settled success and discard the batch, so nothing
//  retried until the next cold start resent it from the achievement baseline. `family` is immune
//  because `activeFamilyId` is already server truth when the client reads it.
//
//  These pin: a rejection keeps the batch, does not spend the transport-failure budget, settles on
//  a later recheck, and cannot recheck forever.
//

import Foundation
import Testing
@testable import LicensePlateApp

@MainActor
struct AchievementUnlockServerCatchUpTests {

    private func makeUser() -> AppUser {
        AppUser(id: "u-1", userName: "kid", firebaseUID: "uid-1")
    }

    private var entitlement: EntitlementState { EntitlementService.shared.entitlementState(for: makeUser()) }

    private func candidate(_ id: String, progress: Int = 10) -> AchievementUnlockSyncCandidate {
        AchievementUnlockSyncCandidate(achievementId: id, lastProgress: progress)
    }

    private static func rejecting(_ ids: [String]) -> [String: Any] {
        ["recordedIds": [], "alreadySyncedIds": [], "rejectedIds": ids]
    }

    private static func recording(_ ids: [String]) -> [String: Any] {
        ["recordedIds": ids, "alreadySyncedIds": [], "rejectedIds": []]
    }

    private struct TransportError: Error {}

    @Test func rejectedCandidateIsKeptPendingInsteadOfDiscarded() async {
        let service = AchievementUnlockSyncService(
            remoteCall: { _ in Self.rejecting(["explorer_10"]) },
            isRestrictedUnconsentedChild: { false }
        )

        let attempt = await service.syncUnlocks(
            user: makeUser(),
            entitlement: entitlement,
            candidates: [candidate("explorer_10")]
        )

        #expect(attempt == .rejectedPendingServerCatchUp)
        #expect(service.hasPendingCandidates)
    }

    /// The whole point: once server progression catches up, the recheck records the unlock and the
    /// XP lands in the same session rather than after a restart.
    @Test func recheckRecordsTheUnlockOnceTheServerCatchesUp() async {
        var serverHasCaughtUp = false
        var sentBatches: [[String]] = []
        let service = AchievementUnlockSyncService(
            remoteCall: { payload in
                let ids = ((payload["candidates"] as? [[String: Any]]) ?? [])
                    .compactMap { $0["achievementId"] as? String }
                    .sorted()
                sentBatches.append(ids)
                return serverHasCaughtUp ? Self.recording(ids) : Self.rejecting(ids)
            },
            isRestrictedUnconsentedChild: { false }
        )
        let user = makeUser()

        await service.syncUnlocks(user: user, entitlement: entitlement, candidates: [candidate("explorer_10")])
        #expect(service.hasPendingCandidates)

        serverHasCaughtUp = true
        await service.retryPendingIfNeeded(user: user, entitlement: entitlement)

        #expect(sentBatches == [["explorer_10"], ["explorer_10"]])
        #expect(!service.hasPendingCandidates)
    }

    /// Only the unverified half is re-queued; anything the server accepted must not be re-sent.
    @Test func onlyRejectedCandidatesStayQueued() async {
        var sentBatches: [[String]] = []
        let service = AchievementUnlockSyncService(
            remoteCall: { payload in
                let ids = ((payload["candidates"] as? [[String: Any]]) ?? [])
                    .compactMap { $0["achievementId"] as? String }
                    .sorted()
                sentBatches.append(ids)
                return [
                    "recordedIds": ["family"],
                    "alreadySyncedIds": [],
                    "rejectedIds": ["explorer_10"],
                ]
            },
            isRestrictedUnconsentedChild: { false }
        )
        let user = makeUser()

        await service.syncUnlocks(
            user: user,
            entitlement: entitlement,
            candidates: [candidate("family", progress: 1), candidate("explorer_10")]
        )
        await service.retryPendingIfNeeded(user: user, entitlement: entitlement)

        #expect(sentBatches == [["explorer_10", "family"], ["explorer_10"]])
    }

    /// A rejection is a "not yet", not a transport failure: it must not eat the three-attempt
    /// failure budget, or a slow server would discard the batch the same way the old code did.
    @Test func rejectionsDoNotSpendTheTransportFailureBudget() async {
        var rejectCount = 0
        var failFrom = false
        var transportAttempts = 0
        let service = AchievementUnlockSyncService(
            remoteCall: { _ in
                if failFrom {
                    transportAttempts += 1
                    throw TransportError()
                }
                rejectCount += 1
                return Self.rejecting(["explorer_10"])
            },
            isRestrictedUnconsentedChild: { false }
        )
        let user = makeUser()

        await service.syncUnlocks(user: user, entitlement: entitlement, candidates: [candidate("explorer_10")])
        await service.retryPendingIfNeeded(user: user, entitlement: entitlement)
        await service.retryPendingIfNeeded(user: user, entitlement: entitlement)
        #expect(rejectCount == 3)
        #expect(service.hasPendingCandidates)

        // The full transport budget is still there: 3 more attempts before the batch is dropped.
        failFrom = true
        for _ in 0..<10 {
            await service.retryPendingIfNeeded(user: user, entitlement: entitlement)
        }
        #expect(transportAttempts == 3)
    }

    /// A candidate the server will never verify must not recheck forever.
    @Test func permanentlyRejectedCandidateIsEventuallyGivenUp() async {
        var callCount = 0
        let service = AchievementUnlockSyncService(
            remoteCall: { _ in
                callCount += 1
                return Self.rejecting(["explorer_10"])
            },
            isRestrictedUnconsentedChild: { false }
        )
        let user = makeUser()

        await service.syncUnlocks(user: user, entitlement: entitlement, candidates: [candidate("explorer_10")])
        for _ in 0..<20 {
            await service.retryPendingIfNeeded(user: user, entitlement: entitlement)
        }

        #expect(!service.hasPendingCandidates)
        // 1 initial + the bounded recheck budget, then it stops calling.
        #expect(callCount == 7)
    }

    @Test func fullyAcceptedResponseClearsTheBatch() async {
        let service = AchievementUnlockSyncService(
            remoteCall: { _ in Self.recording(["explorer_10"]) },
            isRestrictedUnconsentedChild: { false }
        )

        let attempt = await service.syncUnlocks(
            user: makeUser(),
            entitlement: entitlement,
            candidates: [candidate("explorer_10")]
        )

        #expect(attempt == .succeeded)
        #expect(!service.hasPendingCandidates)
    }

    /// A response that carries no verdicts at all (unparseable / empty) stays a success, exactly as
    /// before — only an explicit `rejectedIds` entry re-queues.
    @Test func emptyResponseStillSettlesTheBatch() async {
        let service = AchievementUnlockSyncService(
            remoteCall: { _ in [:] },
            isRestrictedUnconsentedChild: { false }
        )

        let attempt = await service.syncUnlocks(
            user: makeUser(),
            entitlement: entitlement,
            candidates: [candidate("explorer_10")]
        )

        #expect(attempt == .succeeded)
        #expect(!service.hasPendingCandidates)
    }
}
