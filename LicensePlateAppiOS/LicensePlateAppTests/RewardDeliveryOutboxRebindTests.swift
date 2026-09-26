//
//  RewardDeliveryOutboxRebindTests.swift
//  LicensePlateAppTests
//
//  §3.1.1 item 15 — the second cause of the celebration replay: the outbox is UserDefaults keyed by
//  uid, so an identity rebind (FR-60 provision-at-consent, guest → registered link, FR-84 transfer)
//  used to orphan every "already celebrated" mark while the ledger and achievement rows moved on.
//  Also pins the process-lifetime presented ledger's one rule: present once, skip forever after.
//

import Foundation
import Testing
@testable import LicensePlateApp

@MainActor
struct RewardDeliveryOutboxRebindTests {

    /// A private suite per test: `.standard` is the app's own store and must not be touched.
    private func makeOutbox() -> (RewardDeliveryOutbox, UserDefaults, String) {
        let suiteName = "RewardDeliveryOutboxRebindTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (RewardDeliveryOutbox(defaults: defaults), defaults, suiteName)
    }

    private func storageKey(_ userId: String) -> String {
        "rewardDeliveryOutbox.v1.\(userId)"
    }

    // MARK: - The rebind

    @Test func marksFollowTheIdentityRebind() {
        let (outbox, defaults, suite) = makeOutbox()
        defer { defaults.removePersistentDomain(forName: suite) }

        outbox.mark(userId: "local-1", semanticId: "rank-7", state: .presented)
        outbox.mark(userId: "local-1", semanticId: "ach-first_win", state: .dismissed)

        outbox.rebind(from: "local-1", to: "uid-2")

        #expect(outbox.hasPresentedOrDismissed(userId: "uid-2", semanticId: "rank-7"))
        #expect(outbox.hasPresentedOrDismissed(userId: "uid-2", semanticId: "ach-first_win"))
        #expect(outbox.state(userId: "uid-2", semanticId: "ach-first_win") == .dismissed)
        #expect(!outbox.hasPresentedOrDismissed(userId: "local-1", semanticId: "rank-7"))
        #expect(defaults.data(forKey: storageKey("local-1")) == nil, "the old key is dropped")
        #expect(defaults.data(forKey: storageKey("uid-2")) != nil, "and the new one persisted")
    }

    @Test func theRebindIsAUnionAndKeepsTheMarksAlreadyOnTheNewUid() {
        let (outbox, defaults, suite) = makeOutbox()
        defer { defaults.removePersistentDomain(forName: suite) }

        outbox.mark(userId: "uid-2", semanticId: "ach-explorer_10", state: .presented)
        outbox.mark(userId: "local-1", semanticId: "rank-3", state: .presented)

        outbox.rebind(from: "local-1", to: "uid-2")

        #expect(outbox.hasPresentedOrDismissed(userId: "uid-2", semanticId: "ach-explorer_10"))
        #expect(outbox.hasPresentedOrDismissed(userId: "uid-2", semanticId: "rank-3"))
    }

    /// The only way to lose a mark would be to let a `pending` entry overwrite a delivered one.
    @Test func aDeliveredMarkBeatsAPendingOneOnEitherSide() {
        let (outbox, defaults, suite) = makeOutbox()
        defer { defaults.removePersistentDomain(forName: suite) }

        // Delivered on the OLD uid, pending on the new one.
        outbox.mark(userId: "uid-2", semanticId: "ach-first_win", state: .pending)
        outbox.mark(userId: "local-1", semanticId: "ach-first_win", state: .presented)
        // Delivered on the NEW uid, pending on the old one.
        outbox.mark(userId: "uid-2", semanticId: "rank-5", state: .presented)
        outbox.mark(userId: "local-1", semanticId: "rank-5", state: .pending)

        outbox.rebind(from: "local-1", to: "uid-2")

        #expect(outbox.state(userId: "uid-2", semanticId: "ach-first_win") == .presented)
        #expect(outbox.state(userId: "uid-2", semanticId: "rank-5") == .presented)
    }

    @Test func betweenTwoEntriesOfTheSameStrengthTheNewestWins() {
        let older = RewardDeliveryRecord(semanticId: "ach-x", state: .presented, updatedAt: Date(timeIntervalSince1970: 1_000))
        let newer = RewardDeliveryRecord(semanticId: "ach-x", state: .dismissed, updatedAt: Date(timeIntervalSince1970: 2_000))
        #expect(RewardDeliveryOutbox.prefersCandidate(existing: older, candidate: newer))
        #expect(!RewardDeliveryOutbox.prefersCandidate(existing: newer, candidate: older))
        #expect(RewardDeliveryOutbox.isDelivered(.clawedBack))
        #expect(!RewardDeliveryOutbox.isDelivered(.pending))
    }

    @Test func aRebindOntoTheSameUidOrFromAnEmptySideChangesNothing() {
        let (outbox, defaults, suite) = makeOutbox()
        defer { defaults.removePersistentDomain(forName: suite) }

        outbox.mark(userId: "uid-2", semanticId: "rank-2", state: .presented)
        outbox.rebind(from: "uid-2", to: "uid-2")
        outbox.rebind(from: "never-played", to: "uid-2")

        #expect(outbox.hasPresentedOrDismissed(userId: "uid-2", semanticId: "rank-2"))
        #expect(defaults.data(forKey: storageKey("uid-2")) != nil)
    }

    // MARK: - The purge

    @Test func resetClearsThePersistedKeySoAReEarnedRewardIsNotSilenced() {
        let (outbox, defaults, suite) = makeOutbox()
        defer { defaults.removePersistentDomain(forName: suite) }

        outbox.mark(userId: "uid-2", semanticId: "ach-first_win", state: .presented)
        #expect(defaults.data(forKey: storageKey("uid-2")) != nil)

        outbox.reset(userId: "uid-2")

        #expect(!outbox.hasPresentedOrDismissed(userId: "uid-2", semanticId: "ach-first_win"))
        #expect(defaults.data(forKey: storageKey("uid-2")) == nil)
        // And a fresh instance reading the same store agrees (the cache is not hiding the key).
        let reloaded = RewardDeliveryOutbox(defaults: defaults)
        #expect(!reloaded.hasPresentedOrDismissed(userId: "uid-2", semanticId: "ach-first_win"))
    }

    // MARK: - The process-lifetime ledger

    @Test func aSemanticIdIsPresentedOncePerProcessAndSkippedAfterAnIdentityChange() {
        var ledger = CelebrationProcessPresentationLedger()
        let firstBanner = ledger.claim("rank-7")
        let secondBanner = ledger.claim("rank-7")
        let firstPopup = ledger.claim("ach-first_win")
        // A configure-equivalent: the service drops its baseline and the outbox key changes with the
        // uid — neither `configure` nor `resetForSignOut` may clear the ledger, so the id stays
        // claimed.
        let afterIdentityChange = ledger.claim("rank-7")

        #expect(firstBanner)
        #expect(!secondBanner, "the same banner cannot be shown twice in one process")
        #expect(firstPopup)
        #expect(!afterIdentityChange)
        #expect(ledger.presentedCount == 2)
    }

    /// The one exception (2026-09-19): a hard purge deletes the local achievement rows AND the
    /// uid's outbox marks, so a ledger that outlived them would mute an id the player re-earns in
    /// the same process. Reached only from `LocalUserDataPurgeService`.
    @Test func anAccountPurgeClearsTheProcessLedgerSoAReEarnedIdCelebratesAgain() {
        var ledger = CelebrationProcessPresentationLedger()
        let firstPopup = ledger.claim("ach-first_win")
        let secondPopup = ledger.claim("ach-first_win")

        ledger.clearForAccountPurge()
        let countAfterPurge = ledger.presentedCount
        let afterPurge = ledger.claim("ach-first_win")

        #expect(firstPopup)
        #expect(!secondPopup)
        #expect(countAfterPurge == 0)
        #expect(afterPurge, "a re-earned id must be presentable after a purge")
    }
}
