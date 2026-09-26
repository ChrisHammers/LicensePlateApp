//
//  RewardDeliveryOutbox.swift
//  LicensePlateApp
//
//  Durable per-user reward delivery acknowledgments so offline celebrations
//  survive kill/relaunch without double-playing historical rewards.
//
//  §3.1.1 item 15 (2026-09-19): the store is keyed by uid, so an identity rebind used to ORPHAN it.
//  `LocalPlayIdentityRepository.rebindLocalPlayIdentity` carries the ledger and the achievement
//  rows onto the new uid, but nothing carried the already-celebrated marks — an independent second
//  cause of the sign-in / provisioning replay, on top of the listener baseline. `rebind(from:to:)`
//  moves them, and `LocalUserDataPurgeService` clears them, so a purge cannot leave a mark that
//  would silence a re-earned achievement.
//

import Foundation

enum RewardDeliveryState: String, Codable, Sendable {
    case pending
    case presented
    case dismissed
    case clawedBack
}

struct RewardDeliveryRecord: Codable, Equatable, Sendable {
    var semanticId: String
    var state: RewardDeliveryState
    var updatedAt: Date
}

@MainActor
final class RewardDeliveryOutbox {

    static let shared = RewardDeliveryOutbox()

    private let defaults: UserDefaults
    private var cache: [String: [String: RewardDeliveryRecord]] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func state(userId: String, semanticId: String) -> RewardDeliveryState? {
        load(userId: userId)[semanticId]?.state
    }

    func hasPresentedOrDismissed(userId: String, semanticId: String) -> Bool {
        guard let state = state(userId: userId, semanticId: semanticId) else { return false }
        return Self.isDelivered(state)
    }

    func mark(userId: String, semanticId: String, state: RewardDeliveryState) {
        var map = load(userId: userId)
        map[semanticId] = RewardDeliveryRecord(
            semanticId: semanticId,
            state: state,
            updatedAt: Date()
        )
        cache[userId] = map
        persist(userId: userId, map: map)
    }

    /// Moves the marks recorded under `previousUserId` onto `newUserId` and drops the old key.
    ///
    /// UNION, never a loss on either side: an id present on both keeps whichever entry says the
    /// reward was actually delivered (presented / dismissed / clawed back beats pending), and
    /// between two entries of the same strength the newest wins. Silencing one already-seen
    /// celebration is the point; re-showing one is the bug.
    func rebind(from previousUserId: String, to newUserId: String) {
        guard !previousUserId.isEmpty, !newUserId.isEmpty, previousUserId != newUserId else { return }
        let previous = load(userId: previousUserId)
        var merged = load(userId: newUserId)
        var moved = 0
        var mergedCount = 0
        for (semanticId, record) in previous {
            guard let existing = merged[semanticId] else {
                merged[semanticId] = record
                moved += 1
                continue
            }
            mergedCount += 1
            if Self.prefersCandidate(existing: existing, candidate: record) {
                merged[semanticId] = record
            }
        }
        if !previous.isEmpty {
            cache[newUserId] = merged
            persist(userId: newUserId, map: merged)
            reset(userId: previousUserId)
        }
        CelebrationDiagnostics.log(
            "outbox.rebind from=\(CelebrationDiagnostics.shortUid(previousUserId)) to=\(CelebrationDiagnostics.shortUid(newUserId)) moved=\(moved) merged=\(mergedCount)"
        )
    }

    /// The union's tie-break, pure so it can be pinned on its own.
    static func prefersCandidate(existing: RewardDeliveryRecord, candidate: RewardDeliveryRecord) -> Bool {
        let existingDelivered = isDelivered(existing.state)
        let candidateDelivered = isDelivered(candidate.state)
        if existingDelivered != candidateDelivered { return candidateDelivered }
        return candidate.updatedAt > existing.updatedAt
    }

    /// The same partition `hasPresentedOrDismissed` reads: the reward reached the user (or was
    /// taken back), so it must never be shown again.
    static func isDelivered(_ state: RewardDeliveryState) -> Bool {
        switch state {
        case .presented, .dismissed, .clawedBack: return true
        case .pending: return false
        }
    }

    func reset(userId: String) {
        cache[userId] = [:]
        defaults.removeObject(forKey: storageKey(userId))
    }

    func resetAll() {
        cache.removeAll()
    }

    private func load(userId: String) -> [String: RewardDeliveryRecord] {
        if let cached = cache[userId] { return cached }
        guard let data = defaults.data(forKey: storageKey(userId)),
              let decoded = try? JSONDecoder().decode([String: RewardDeliveryRecord].self, from: data)
        else {
            cache[userId] = [:]
            return [:]
        }
        cache[userId] = decoded
        return decoded
    }

    private func persist(userId: String, map: [String: RewardDeliveryRecord]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        defaults.set(data, forKey: storageKey(userId))
    }

    private func storageKey(_ userId: String) -> String {
        "rewardDeliveryOutbox.v1.\(userId)"
    }
}
