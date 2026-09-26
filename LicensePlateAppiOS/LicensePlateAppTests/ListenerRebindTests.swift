//
//  ListenerRebindTests.swift
//  LicensePlateAppTests
//
//  Pins the listen-error lifecycle of the three progression listeners (XpGrantRemoteRepository,
//  UserProgressionRepository, UserAchievementRemoteRepository): an error callback never latches
//  `hasReceivedInitialSnapshot`, the dead registration is released, and the rebind is bounded.
//  No backend: the repositories take a fake `attach` and a manual clock.
//

import Foundation
import Testing
import FirebaseFirestore
@testable import LicensePlateApp

private final class FakeRegistration: NSObject, ListenerRegistration {
    private(set) var removeCount = 0
    func remove() { removeCount += 1 }
}

/// A sleep returns only when the test says so; the requested delays are the backoff under test.
@MainActor
private final class ManualClock {
    private(set) var requestedDelays: [TimeInterval] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func sleep(_ seconds: TimeInterval) async {
        requestedDelays.append(seconds)
        await withCheckedContinuation { waiters.append($0) }
    }

    /// Lets the oldest pending sleep return (a cancelled task still has to be woken to finish).
    func fire() {
        waiters.removeFirst().resume()
    }
}

@MainActor
private final class AttachRecorder<Snapshot> {
    private(set) var userIds: [String] = []
    private(set) var registrations: [FakeRegistration] = []
    private var handlers: [(Snapshot?, Error?) -> Void] = []

    func attach(_ userId: String, _ onEvent: @escaping (Snapshot?, Error?) -> Void) -> ListenerRegistration {
        userIds.append(userId)
        handlers.append(onEvent)
        let registration = FakeRegistration()
        registrations.append(registration)
        return registration
    }

    /// Delivers permission-denied to the `index`-th attached listener, the way Firestore does.
    func failListen(_ index: Int) {
        handlers[index](
            nil,
            NSError(domain: FirestoreErrorDomain, code: FirestoreErrorCode.permissionDenied.rawValue)
        )
    }
}

@MainActor
struct ListenerRebindTests {

    enum Repo: String, CaseIterable {
        case xpGrants, userProgression, userAchievements
    }

    /// One repository under test, reduced to what the shared lifecycle pins need.
    @MainActor
    private final class Harness {
        let clock: ManualClock
        let start: (String) -> Void
        let stop: () -> Void
        let hasReceivedInitialSnapshot: () -> Bool
        let failListen: (Int) -> Void
        let attachedUserIds: () -> [String]
        let registrations: () -> [FakeRegistration]

        init(_ kind: Repo) {
            let clock = ManualClock()
            let scheduler = ListenerRebindScheduler(sleep: { await clock.sleep($0) })
            self.clock = clock
            switch kind {
            case .xpGrants:
                let recorder = AttachRecorder<QuerySnapshot>()
                let repo = XpGrantRemoteRepository(
                    attach: { recorder.attach($0, $1) },
                    rebindScheduler: scheduler
                )
                start = { repo.startListening(userId: $0) }
                stop = { repo.stopListening() }
                hasReceivedInitialSnapshot = { repo.hasReceivedInitialSnapshot }
                failListen = { recorder.failListen($0) }
                attachedUserIds = { recorder.userIds }
                registrations = { recorder.registrations }
            case .userProgression:
                let recorder = AttachRecorder<DocumentSnapshot>()
                let repo = UserProgressionRepository(
                    attach: { recorder.attach($0, $1) },
                    rebindScheduler: scheduler
                )
                start = { repo.startListening(userId: $0) }
                stop = { repo.stopListening() }
                hasReceivedInitialSnapshot = { repo.hasReceivedInitialSnapshot }
                failListen = { recorder.failListen($0) }
                attachedUserIds = { recorder.userIds }
                registrations = { recorder.registrations }
            case .userAchievements:
                let recorder = AttachRecorder<QuerySnapshot>()
                let repo = UserAchievementRemoteRepository(
                    attach: { recorder.attach($0, $1) },
                    rebindScheduler: scheduler
                )
                start = { repo.startListening(userId: $0) }
                stop = { repo.stopListening() }
                hasReceivedInitialSnapshot = { repo.hasReceivedInitialSnapshot }
                failListen = { recorder.failListen($0) }
                attachedUserIds = { recorder.userIds }
                registrations = { recorder.registrations }
            }
        }
    }

    /// The repositories hop their callback through `Task { @MainActor }`, and the scheduler's task
    /// resumes on the main actor too: yield until the expected state lands (bounded).
    private func settle(until done: () -> Bool = { false }) async {
        for _ in 0..<50 {
            if done() { return }
            await Task.yield()
        }
    }

    // MARK: - ListenerRebindScheduler

    @Test func schedulerWalksTheBackoffAndStopsAtTheBound() async {
        let clock = ManualClock()
        let scheduler = ListenerRebindScheduler(sleep: { await clock.sleep($0) })
        var rebinds = 0

        for expected in ListenerRebindScheduler.defaultDelays {
            #expect(scheduler.scheduleRebind { rebinds += 1 } == expected)
            await settle { clock.requestedDelays.last == expected }
            let before = rebinds
            #expect(before == clock.requestedDelays.count - 1, "the rebind waits for its delay")
            clock.fire()
            await settle { rebinds == before + 1 }
        }

        #expect(ListenerRebindScheduler.defaultDelays == [1, 2, 4, 8, 16])
        #expect(rebinds == 5)
        #expect(scheduler.scheduleRebind { rebinds += 1 } == nil, "the budget is spent")
        await settle()
        #expect(rebinds == 5)
        #expect(clock.requestedDelays.count == 5)
    }

    @Test func schedulerResetDropsThePendingRebindAndRefillsTheBudget() async {
        let clock = ManualClock()
        let scheduler = ListenerRebindScheduler(sleep: { await clock.sleep($0) })
        var rebinds = 0

        #expect(scheduler.scheduleRebind { rebinds += 1 } == 1)
        await settle { clock.requestedDelays.count == 1 }
        scheduler.reset()
        clock.fire()
        await settle()
        #expect(rebinds == 0, "a reset (stop / uid change) cancels the pending rebind")

        #expect(scheduler.scheduleRebind { rebinds += 1 } == 1, "and the next failure starts over")
    }

    @Test func schedulerRefillsOnlyOnAServerConfirmedSnapshot() async {
        let scheduler = ListenerRebindScheduler(delays: [1, 2], sleep: { _ in })
        #expect(scheduler.scheduleRebind {} == 1)
        #expect(scheduler.scheduleRebind {} == 2)
        #expect(scheduler.scheduleRebind {} == nil)

        scheduler.noteServerConfirmedSnapshot()
        #expect(scheduler.scheduleRebind {} == 1)
    }

    // MARK: - All three repositories

    /// The defect: the error callback set `hasReceivedInitialSnapshot` with nothing delivered, so
    /// readers took an empty repository for a hydrated one.
    @Test(arguments: Repo.allCases)
    func aListenErrorNeverLatchesTheInitialSnapshotFlag(_ kind: Repo) async {
        let harness = Harness(kind)
        harness.start("u1")
        harness.failListen(0)
        await settle { harness.clock.requestedDelays.count == 1 }

        #expect(!harness.hasReceivedInitialSnapshot())
        #expect(harness.registrations()[0].removeCount == 1, "the dead registration is released")
        #expect(harness.clock.requestedDelays == [1], "and a rebind is on the clock")
        #expect(harness.attachedUserIds() == ["u1"], "but not before its delay")
    }

    @Test(arguments: Repo.allCases)
    func aListenErrorRebindsTheSameUidAndStaysUnlatched(_ kind: Repo) async {
        let harness = Harness(kind)
        harness.start("u1")
        harness.failListen(0)
        await settle { harness.clock.requestedDelays.count == 1 }
        harness.clock.fire()
        await settle { harness.attachedUserIds().count == 2 }

        #expect(harness.attachedUserIds() == ["u1", "u1"])
        #expect(!harness.hasReceivedInitialSnapshot())
    }

    @Test(arguments: Repo.allCases)
    func theRebindIsBounded(_ kind: Repo) async {
        let harness = Harness(kind)
        harness.start("u1")
        for attempt in 0..<5 {
            harness.failListen(attempt)
            await settle { harness.clock.requestedDelays.count == attempt + 1 }
            harness.clock.fire()
            await settle { harness.attachedUserIds().count == attempt + 2 }
        }
        #expect(harness.clock.requestedDelays == [1, 2, 4, 8, 16])
        #expect(harness.attachedUserIds().count == 6)

        harness.failListen(5)
        await settle { harness.registrations()[5].removeCount == 1 }
        await settle()

        #expect(harness.registrations()[5].removeCount == 1)
        #expect(harness.clock.requestedDelays.count == 5, "a persistently denied listen goes quiet")
        #expect(harness.attachedUserIds().count == 6)
        #expect(!harness.hasReceivedInitialSnapshot())
    }

    /// The other half of the defect: `startListening`'s same-uid guard took the dead (non-nil)
    /// registration for a live listener, so nothing could rebind until the next uid change.
    @Test(arguments: Repo.allCases)
    func startListeningForTheSameUidAfterAnErrorRebindsAtOnce(_ kind: Repo) async {
        let harness = Harness(kind)
        harness.start("u1")
        harness.failListen(0)
        await settle { harness.clock.requestedDelays.count == 1 }

        harness.start("u1")
        #expect(harness.attachedUserIds() == ["u1", "u1"])

        harness.clock.fire()
        await settle()
        #expect(harness.attachedUserIds().count == 2, "the superseded rebind never fires")

        harness.start("u1")
        #expect(harness.attachedUserIds().count == 2, "a live listener is still left alone")
    }

    @Test(arguments: Repo.allCases)
    func aUidChangeCancelsThePendingRebindAndRefillsTheBudget(_ kind: Repo) async {
        let harness = Harness(kind)
        harness.start("u1")
        harness.failListen(0)
        await settle { harness.clock.requestedDelays.count == 1 }

        harness.start("u2")
        harness.clock.fire()
        await settle()
        #expect(harness.attachedUserIds() == ["u1", "u2"], "u1 is never rebound over u2")

        harness.failListen(1)
        await settle { harness.clock.requestedDelays.count == 2 }
        #expect(harness.clock.requestedDelays == [1, 1], "u2 starts on a full budget")
    }

    @Test(arguments: Repo.allCases)
    func stopListeningCancelsThePendingRebind(_ kind: Repo) async {
        let harness = Harness(kind)
        harness.start("u1")
        harness.failListen(0)
        await settle { harness.clock.requestedDelays.count == 1 }

        harness.stop()
        harness.clock.fire()
        await settle()
        #expect(harness.attachedUserIds() == ["u1"])
    }

    /// Sign-out denies the old uid's listen; its error callback can land after the next uid is
    /// already bound. It must not tear down that binding's listener or spend its budget.
    @Test(arguments: Repo.allCases)
    func aLateErrorFromASupersededBindingIsDropped(_ kind: Repo) async {
        let harness = Harness(kind)
        harness.start("u1")
        harness.start("u2")
        harness.failListen(0)
        await settle()

        #expect(harness.registrations()[1].removeCount == 0)
        #expect(harness.clock.requestedDelays.isEmpty)
        #expect(harness.attachedUserIds() == ["u1", "u2"])
    }

    // MARK: - XpGrantRemoteRepository (item 12's watermark)

    /// The rebind is a full bind: a new generation (so the XP toast re-earns its seal and absorbs,
    /// never replays) with both flags down, and the uid kept so the toast does not read a mismatch.
    @Test func aGrantsListenErrorKeepsTheUidAndRebindsOnANewGeneration() async {
        let clock = ManualClock()
        let recorder = AttachRecorder<QuerySnapshot>()
        let repo = XpGrantRemoteRepository(
            attach: { recorder.attach($0, $1) },
            rebindScheduler: ListenerRebindScheduler(sleep: { await clock.sleep($0) })
        )
        repo.startListening(userId: "u1")
        let failedGeneration = repo.bindingGeneration

        recorder.failListen(0)
        await settle { clock.requestedDelays.count == 1 }
        #expect(repo.boundUserId == "u1")
        #expect(!repo.hasReceivedInitialSnapshot)
        #expect(!repo.hasReceivedServerSnapshot)
        #expect(repo.grants.isEmpty)
        #expect(repo.bindingGeneration == failedGeneration)

        clock.fire()
        await settle { recorder.userIds.count == 2 }
        #expect(repo.boundUserId == "u1")
        #expect(repo.bindingGeneration != failedGeneration)
        #expect(!repo.hasReceivedServerSnapshot)
    }
}
