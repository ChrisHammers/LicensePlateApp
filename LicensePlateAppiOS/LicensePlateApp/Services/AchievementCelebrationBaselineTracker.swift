//
//  AchievementCelebrationBaselineTracker.swift
//  LicensePlateApp
//
//  Pure baseline / transition bookkeeping for AchievementUnlockCelebrationService, split out so
//  the "what is history, what is a gain" rules are unit-testable without Firestore or SwiftData.
//
//  TWO halves, and neither may break the other (§3.1.1 item 15, 2026-09-18 — the celebration's
//  port of item 12):
//   • LOCAL: the attach baseline is the first snapshot after configure, sealed as soon as local
//     progression exists, with no remote gate of any kind — that is what keeps a rank-up or an
//     unlock earned OFFLINE celebrating (dc7887e).
//   • REMOTE: until the server has confirmed the CURRENT binding of both listeners, whatever the
//     server-backed state ALONE already shows is history, not a gain. On a uid this device never
//     cached (reinstall, sign-in, FR-84 transfer) the local baseline is empty by construction and
//     the whole account arrives one round trip later; the pre-item-15 code read that as a rank-up
//     (deterministic) and as N unlocks (a race between the two listeners).
//     Attribution is by CONTENT, not by timing: a rank at or below the absorbed history rank and
//     an achievement the server-backed view already showed unlocked are never transitions, however
//     late `effectiveTotals` catches up with the repository (one 80 ms debounce behind it) and
//     whatever else lands in the same debounced refresh. A gain ABOVE that line still celebrates.
//     After the seal the absorbed set is frozen and every transition is a real gain.
//     Accepted loss, same class as OD-15: a rank or unlock that first becomes visible INSIDE the
//     sealing sync (earned on another device, or awarded by a peer's trip end while this device
//     was closed or offline) counts but is not celebrated.
//

import Foundation

struct AchievementCelebrationBaselineTracker {

    /// What the two server-backed listeners (`user_progression/{uid}` and
    /// `user_achievements/{uid}/achievements`) report for this refresh.
    struct RemoteWatermark: Equatable {
        /// `"<uid>#<progressionIdentityEpoch>#<achievementsIdentityEpoch>"`, non-nil only while
        /// BOTH listeners are bound to the configured uid. nil = fail closed: nothing remote is
        /// absorbed and nothing seals (a snapshot of another identity is not this user's history).
        /// Keyed on the repositories' `identityEpoch`, which moves only on a real (re)bind or a
        /// stop — NOT on their `bindingGeneration`, which the listen-error rebind also bumps and
        /// which would therefore re-open the absorb window on every transient listen failure
        /// (§3.1.1 item 15, 2026-09-19).
        var bindingKey: String?
        /// Every server-backed input the history is read from has answered: both listeners have
        /// delivered a server-confirmed snapshot, and the public lifetime stats profile listener
        /// has delivered its first snapshot (a missing document counts). The entitlement / family
        /// flags have no such signal and are the known residual.
        var isServerConfirmed: Bool
    }

    struct RemoteAbsorption: Equatable {
        var history: AchievementProgressSnapshot
        var newlyAbsorbedIds: [String]
        var newlyAbsorbedRankLevel: Int?
        var sealed: Bool
    }

    struct Step: Equatable {
        /// Non-nil exactly once per identity epoch: the local attach baseline.
        var localBaseline: AchievementProgressSnapshot?
        /// Non-nil when this refresh absorbed new remote history and/or sealed the binding.
        var remoteAbsorption: RemoteAbsorption?
        var rankUpLevel: Int?
        var newlyUnlockedIds: [String]
    }

    private(set) var previousSnapshot: AchievementProgressSnapshot?
    private var firstSnapshotAfterConfigure: AchievementProgressSnapshot?
    private(set) var hasBaseline = false
    /// The binding whose server-confirmed snapshot closed the remote history line. An IDENTITY
    /// rebind (stop/start, a new uid) changes the key, so it re-earns the seal by construction;
    /// the rebind after a transient listen error does not, so a gain the server delivers once the
    /// listener is back is a gain and not history.
    private(set) var sealedBindingKey: String?
    /// Rank 1 is nobody's rank-up, so it is the floor rather than something to absorb.
    private var absorbedRankLevel = 1
    private var absorbedAchievementIds = Set<String>()

    mutating func reset() {
        self = AchievementCelebrationBaselineTracker()
    }

    /// One refresh. Returns nil while the service is not hydrated (nothing to do yet).
    /// `serverBackedSnapshot` is only evaluated while the current binding is unsealed.
    mutating func ingest(
        snapshot: AchievementProgressSnapshot,
        isHydrated: Bool,
        remote: RemoteWatermark,
        serverBackedSnapshot: () -> AchievementProgressSnapshot
    ) -> Step? {
        if firstSnapshotAfterConfigure == nil {
            firstSnapshotAfterConfigure = snapshot
        }
        guard isHydrated else { return nil }

        var step = Step(localBaseline: nil, remoteAbsorption: nil, rankUpLevel: nil, newlyUnlockedIds: [])
        if !hasBaseline {
            let baseline = firstSnapshotAfterConfigure ?? snapshot
            step.localBaseline = baseline
            previousSnapshot = baseline
            hasBaseline = true
        }
        guard let previous = previousSnapshot else { return step }

        // The remote half, decided before the transitions are read.
        if let key = remote.bindingKey, sealedBindingKey != key {
            let history = serverBackedSnapshot()
            let newIds = history.statuses
                .filter { $0.value.isUnlocked }
                .map(\.key)
                .filter { absorbedAchievementIds.insert($0).inserted }
                .sorted()
            var newRankLevel: Int?
            if history.rankLevel > absorbedRankLevel {
                absorbedRankLevel = history.rankLevel
                newRankLevel = history.rankLevel
            }
            if remote.isServerConfirmed {
                sealedBindingKey = key
            }
            if !newIds.isEmpty || newRankLevel != nil || remote.isServerConfirmed {
                step.remoteAbsorption = RemoteAbsorption(
                    history: history,
                    newlyAbsorbedIds: newIds,
                    newlyAbsorbedRankLevel: newRankLevel,
                    sealed: remote.isServerConfirmed
                )
            }
        }

        if let level = AchievementUnlockTransitionDetector.rankUpLevel(
            previous: previous.rankLevel,
            nextLevel: snapshot.rankLevel
        ), level > absorbedRankLevel {
            step.rankUpLevel = level
        }
        step.newlyUnlockedIds = AchievementUnlockTransitionDetector.newlyUnlockedAchievementIds(
            previous: previous.statuses,
            next: snapshot.statuses
        )
        .filter { !absorbedAchievementIds.contains($0) }
        previousSnapshot = snapshot
        return step
    }
}
