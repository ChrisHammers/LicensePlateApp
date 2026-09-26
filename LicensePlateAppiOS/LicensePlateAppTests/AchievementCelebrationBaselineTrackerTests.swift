//
//  AchievementCelebrationBaselineTrackerTests.swift
//  LicensePlateAppTests
//
//  §3.1.1 item 15 — the rank / achievement celebration must not replay history that first
//  arrives from the server AFTER the local attach baseline (reinstall, sign-in, FR-84 transfer:
//  a uid this device never cached), and must keep celebrating local gains while unsealed (offline).
//

import Foundation
import Testing
@testable import LicensePlateApp

struct AchievementCelebrationBaselineTrackerTests {

    private typealias Tracker = AchievementCelebrationBaselineTracker

    // MARK: Fixtures

    private let unbound = Tracker.RemoteWatermark(bindingKey: nil, isServerConfirmed: false)
    private let unsealed = Tracker.RemoteWatermark(bindingKey: "u1#1#1", isServerConfirmed: false)
    private let sealed = Tracker.RemoteWatermark(bindingKey: "u1#1#1", isServerConfirmed: true)

    private func snapshot(rank: Int, xp: Int, unlocked: [String] = []) -> AchievementProgressSnapshot {
        var statuses: [String: AchievementStatus] = ["first_win": .locked, "explorer_10": .locked, "explorer_25": .locked]
        for id in unlocked {
            statuses[id] = AchievementStatus(isUnlocked: true, progress: 1)
        }
        return AchievementProgressSnapshot(statuses: statuses, rankLevel: rank, totalXp: xp)
    }

    private var empty: AchievementProgressSnapshot { snapshot(rank: 1, xp: 0) }

    /// Attach on a uid this device never cached: the first refresh sees nothing, and local
    /// progression (an EMPTY server snapshot + no pending) hydrates the service ~80 ms later.
    private func attachedOnNeverCachedUid() -> Tracker {
        var tracker = Tracker()
        _ = tracker.ingest(snapshot: empty, isHydrated: false, remote: unsealed) { self.empty }
        let step = tracker.ingest(snapshot: empty, isHydrated: true, remote: unsealed) { self.empty }
        #expect(step?.localBaseline == empty)
        #expect(step?.rankUpLevel == nil)
        return tracker
    }

    // MARK: The replay (RED before the fix)

    @Test func historicalRankArrivingFromTheServerIsNotARankUp() {
        var tracker = attachedOnNeverCachedUid()
        // The progression doc's server round trip lands: 5 000 lifetime XP, rank 7.
        let history = snapshot(rank: 7, xp: 5_000)
        let step = tracker.ingest(snapshot: history, isHydrated: true, remote: unsealed) { history }
        #expect(step?.rankUpLevel == nil)
        #expect(step?.remoteAbsorption?.newlyAbsorbedRankLevel == 7)
        #expect(step?.remoteAbsorption?.sealed == false)
    }

    @Test func historicalAchievementsSurfacingAfterTheProgressionLagAreNotUnlocks() {
        var tracker = attachedOnNeverCachedUid()
        // Refresh A: the repository already holds the server doc, but `effectiveTotals` trails it
        // by one debounce — the FULL snapshot still shows every computed achievement locked, while
        // the server-backed view (built from the repository directly) already shows them unlocked.
        let lagging = snapshot(rank: 7, xp: 5_000)
        let serverView = snapshot(rank: 7, xp: 5_000, unlocked: ["explorer_10", "first_win"])
        let stepA = tracker.ingest(snapshot: lagging, isHydrated: true, remote: sealed) { serverView }
        #expect(stepA?.newlyUnlockedIds == [])
        #expect(stepA?.remoteAbsorption?.newlyAbsorbedIds == ["explorer_10", "first_win"])
        #expect(stepA?.remoteAbsorption?.sealed == true)
        // Refresh B: `effectiveTotals` caught up, AFTER the seal. Still history.
        let stepB = tracker.ingest(snapshot: serverView, isHydrated: true, remote: sealed) { serverView }
        #expect(stepB?.newlyUnlockedIds == [])
        #expect(stepB?.rankUpLevel == nil)
        #expect(stepB?.remoteAbsorption == nil)
    }

    @Test func historyArrivingInTwoSnapshotsIsAbsorbedUntilBothBindingsAreServerConfirmed() {
        var tracker = attachedOnNeverCachedUid()
        let first = snapshot(rank: 4, xp: 1_200, unlocked: ["first_win"])
        let stepOne = tracker.ingest(snapshot: first, isHydrated: true, remote: unsealed) { first }
        #expect(stepOne?.rankUpLevel == nil)
        #expect(stepOne?.newlyUnlockedIds == [])
        #expect(stepOne?.remoteAbsorption?.sealed == false)
        // A partial cache topped up by the server: more history, and the seal.
        let second = snapshot(rank: 7, xp: 5_000, unlocked: ["first_win", "explorer_10"])
        let stepTwo = tracker.ingest(snapshot: second, isHydrated: true, remote: sealed) { second }
        #expect(stepTwo?.rankUpLevel == nil)
        #expect(stepTwo?.newlyUnlockedIds == [])
        #expect(stepTwo?.remoteAbsorption?.newlyAbsorbedIds == ["explorer_10"])
        #expect(stepTwo?.remoteAbsorption?.newlyAbsorbedRankLevel == 7)
        #expect(stepTwo?.remoteAbsorption?.sealed == true)
    }

    // MARK: Not a mute

    @Test func gainsAfterTheSealCelebrate() {
        var tracker = attachedOnNeverCachedUid()
        let history = snapshot(rank: 7, xp: 5_000, unlocked: ["first_win"])
        _ = tracker.ingest(snapshot: history, isHydrated: true, remote: sealed) { history }
        // A peer ends the trip: the server writes placement XP and the player crosses rank 8.
        let gained = snapshot(rank: 8, xp: 6_400, unlocked: ["first_win", "explorer_10"])
        let step = tracker.ingest(snapshot: gained, isHydrated: true, remote: sealed) { gained }
        #expect(step?.rankUpLevel == 8)
        #expect(step?.newlyUnlockedIds == ["explorer_10"])
        #expect(step?.remoteAbsorption == nil)
    }

    @Test func localGainsWhileUnsealedStillCelebrate() {
        // Offline launch on a warm device: the cached view is history, the server never answers.
        var tracker = Tracker()
        let cached = snapshot(rank: 3, xp: 990)
        _ = tracker.ingest(snapshot: cached, isHydrated: true, remote: unsealed) { cached }
        // A plate found offline: provisional XP crosses rank 4 and unlocks explorer_10. The
        // server-backed view has not moved — it cannot, the device is offline.
        let afterFind = snapshot(rank: 4, xp: 1_000, unlocked: ["explorer_10"])
        let step = tracker.ingest(snapshot: afterFind, isHydrated: true, remote: unsealed) { cached }
        #expect(step?.rankUpLevel == 4)
        #expect(step?.newlyUnlockedIds == ["explorer_10"])
    }

    @Test func aLocalGainCoalescedWithArrivingHistoryCelebratesOnlyTheGain() {
        var tracker = attachedOnNeverCachedUid()
        // One debounced refresh sees BOTH the server history (rank 7) and a plate found in the
        // same 80 ms whose provisional XP crosses rank 8.
        let serverView = snapshot(rank: 7, xp: 6_395, unlocked: ["first_win"])
        let full = snapshot(rank: 8, xp: 6_405, unlocked: ["first_win", "explorer_10"])
        let step = tracker.ingest(snapshot: full, isHydrated: true, remote: unsealed) { serverView }
        #expect(step?.rankUpLevel == 8)
        #expect(step?.newlyUnlockedIds == ["explorer_10"])
        #expect(step?.remoteAbsorption?.newlyAbsorbedIds == ["first_win"])
    }

    // MARK: Binding discipline

    @Test func aListenerBoundToAnotherUidAbsorbsNothingAndNeverSeals() {
        var tracker = Tracker()
        _ = tracker.ingest(snapshot: empty, isHydrated: true, remote: unbound) { self.empty }
        let foreign = snapshot(rank: 9, xp: 9_000, unlocked: ["first_win"])
        let step = tracker.ingest(snapshot: empty, isHydrated: true, remote: unbound) { foreign }
        #expect(step?.remoteAbsorption == nil)
        #expect(tracker.sealedBindingKey == nil)
    }

    /// The error-driven rebind (slice A's `listenFailed` → `attachListener`) bumps
    /// `bindingGeneration` but NOT `identityEpoch`, and the seal key is built from `identityEpoch`
    /// — so the key does not move, the absorb window does not re-open, and the first gain the
    /// server delivers once the listener is back is a gain. Pre-fix this arrived as a NEW key and
    /// was absorbed as history (and durably marked presented). The same-key/`isServerConfirmed`
    /// false variant is the belt-and-braces case: the seal is keyed on the key alone.
    @Test func aListenErrorRebindKeepsTheSealAndTheNextServerGainCelebrates() {
        var tracker = attachedOnNeverCachedUid()
        let history = snapshot(rank: 7, xp: 5_000, unlocked: ["first_win"])
        _ = tracker.ingest(snapshot: history, isHydrated: true, remote: sealed) { history }
        #expect(tracker.sealedBindingKey == "u1#1#1")
        // The listen errors and rebinds: same identity epoch, so the same key.
        let afterRebind = Tracker.RemoteWatermark(bindingKey: "u1#1#1", isServerConfirmed: false)
        let peerAward = snapshot(rank: 8, xp: 6_400, unlocked: ["first_win", "explorer_10"])
        let step = tracker.ingest(snapshot: peerAward, isHydrated: true, remote: afterRebind) { peerAward }
        #expect(step?.remoteAbsorption == nil)
        #expect(step?.rankUpLevel == 8)
        #expect(step?.newlyUnlockedIds == ["explorer_10"])
        #expect(tracker.sealedBindingKey == "u1#1#1")
    }

    @Test func aRebindReEarnsTheSeal() {
        var tracker = attachedOnNeverCachedUid()
        let history = snapshot(rank: 5, xp: 2_000)
        _ = tracker.ingest(snapshot: history, isHydrated: true, remote: sealed) { history }
        #expect(tracker.sealedBindingKey == "u1#1#1")
        // A real IDENTITY rebind (stop/start, FR-84 transfer): the progression repository's
        // `identityEpoch` moves, so the key does — unsealed again until the server confirms.
        let rebound = Tracker.RemoteWatermark(bindingKey: "u1#2#1", isServerConfirmed: false)
        let more = snapshot(rank: 6, xp: 3_000)
        let step = tracker.ingest(snapshot: more, isHydrated: true, remote: rebound) { more }
        #expect(step?.rankUpLevel == nil)
        #expect(step?.remoteAbsorption?.sealed == false)
    }

    // MARK: Unchanged behaviour

    @Test func nothingHappensBeforeHydration() {
        var tracker = Tracker()
        let step = tracker.ingest(snapshot: empty, isHydrated: false, remote: unsealed) { self.empty }
        #expect(step == nil)
        #expect(tracker.hasBaseline == false)
    }

    @Test func theLocalBaselineIsTheFirstSnapshotAfterConfigure() {
        var tracker = Tracker()
        let atAttach = snapshot(rank: 2, xp: 300)
        _ = tracker.ingest(snapshot: atAttach, isHydrated: false, remote: unbound) { self.empty }
        // A gain between attach and hydration is still a gain (pre-existing rule, dc7887e).
        let later = snapshot(rank: 3, xp: 700)
        let step = tracker.ingest(snapshot: later, isHydrated: true, remote: unbound) { self.empty }
        #expect(step?.localBaseline == atAttach)
        #expect(step?.rankUpLevel == 3)
    }
}
