//
//  PublicLifetimeStatsRepository.swift
//  LicensePlateApp
//
//  Firestore read + SwiftData cache for `public_lifetime_stats`. No client writes.
//

import Combine
import Foundation
import SwiftData
import FirebaseFirestore

@MainActor
final class PublicLifetimeStatsRepository: ObservableObject {

    static let shared = PublicLifetimeStatsRepository()

    private let db = Firestore.firestore()
    private var modelContext: ModelContext?

    private enum ListenerReason: Int, Comparable {
        case friend = 1
        case family = 2
        case profile = 3

        static func < (a: ListenerReason, b: ListenerReason) -> Bool {
            a.rawValue < b.rawValue
        }
    }

    private var listeners: [String: ListenerRegistration] = [:]
    /// Highest-priority reason we attached this listener (profile beats family beats friend).
    private var listenerReason: [String: ListenerReason] = [:]

    private var profileUserId: String?
    private var familyPinnedUserIds = Set<String>()
    /// Profile user's id once its Firestore listener has fired at least once (including missing doc).
    private(set) var profileInitialSnapshotReceivedForUserId: String?

    @Published private(set) var snapshots: [String: UserLifetimeStats] = [:]

    private init() {}

    func setModelContext(_ context: ModelContext) {
        modelContext = context
    }

    func setProfileUserId(_ userId: String?) {
        profileUserId = userId
        if userId != profileInitialSnapshotReceivedForUserId {
            profileInitialSnapshotReceivedForUserId = nil
        }
    }

    func hasReceivedInitialProfileSnapshot(forUserId userId: String) -> Bool {
        profileInitialSnapshotReceivedForUserId == userId
    }

    func updateFamilyPinnedUserIds(_ ids: Set<String>) {
        familyPinnedUserIds = ids
        for uid in Array(listeners.keys) {
            if listenerReason[uid] == .family && !ids.contains(uid) && uid != profileUserId {
                stopListening(userId: uid)
            }
        }
        for uid in ids {
            ensureListening(userId: uid, reason: .family)
        }
    }

    func ensureObservingFriend(userId: String) {
        guard !userId.isEmpty else { return }
        if userId == profileUserId {
            ensureObservingProfileUser(userId)
            return
        }
        if familyPinnedUserIds.contains(userId) {
            ensureListening(userId: userId, reason: .family)
            return
        }
        evictFriendsIfNeededBeforeAdding(incomingUserId: userId)
        ensureListening(userId: userId, reason: .friend)
    }

    func ensureObservingProfileUser(_ userId: String) {
        guard !userId.isEmpty else { return }
        profileUserId = userId
        ensureListening(userId: userId, reason: .profile)
    }

    func snapshot(forUserId userId: String) -> UserLifetimeStats? {
        snapshots[userId]
    }

    func cachedStatsFromDisk(forUserId userId: String) throws -> UserLifetimeStats? {
        guard let ctx = modelContext else { return nil }
        let descriptor = FetchDescriptor<PublicLifetimeStatsCacheEntity>(
            predicate: #Predicate<PublicLifetimeStatsCacheEntity> { $0.userId == userId }
        )
        guard let entity = try ctx.fetch(descriptor).first else { return nil }
        return UserLifetimeStats(
            totalCompletedTrips: entity.totalCompletedTrips,
            totalGamesPlayed: entity.totalGamesPlayed,
            totalDiscoveries: entity.totalDiscoveries,
            totalWeightedScore: entity.totalWeightedScore,
            familyOnlyTripsCount: entity.familyOnlyTripsCount,
            friendsOnlyTripsCount: entity.friendsOnlyTripsCount,
            mixedFriendsFamilyTripsCount: entity.mixedFriendsFamilyTripsCount,
            entireFamilyTripsCount: entity.entireFamilyTripsCount,
            lastComputedAt: entity.lastServerUpdatedAt
        )
    }

    func stopListening(userId: String) {
        listeners[userId]?.remove()
        listeners[userId] = nil
        listenerReason[userId] = nil
        snapshots[userId] = nil
    }

    func stopAllListeners() {
        for reg in listeners.values {
            reg.remove()
        }
        listeners.removeAll()
        listenerReason.removeAll()
        snapshots.removeAll()
    }

    // MARK: - Private

    private func observedFriendUserIds() -> Set<String> {
        var result = Set<String>()
        for (uid, reason) in listenerReason where reason == .friend {
            result.insert(uid)
        }
        return result
    }

    private func evictFriendsIfNeededBeforeAdding(incomingUserId: String) {
        let friends = observedFriendUserIds()
        guard let ctx = modelContext else { return }
        var records: [(String, Date)] = []
        for uid in friends {
            let descriptor = FetchDescriptor<PublicLifetimeStatsCacheEntity>(
                predicate: #Predicate<PublicLifetimeStatsCacheEntity> { $0.userId == uid }
            )
            if let row = try? ctx.fetch(descriptor).first {
                records.append((uid, row.lastAccessedAt))
            } else {
                records.append((uid, .distantPast))
            }
        }
        let victims = PublicLifetimeStatsCachePolicy.friendUserIdsToEvict(
            observedFriendIds: friends,
            accessRecords: records.map { (userId: $0.0, lastAccessedAt: $0.1) },
            incomingUserId: incomingUserId
        )
        for uid in victims {
            stopListening(userId: uid)
        }
    }

    private func ensureListening(userId: String, reason: ListenerReason) {
        let mergedReason: ListenerReason
        if let existing = listenerReason[userId] {
            mergedReason = max(existing, reason)
        } else {
            mergedReason = reason
        }
        listenerReason[userId] = mergedReason
        touchAccess(userId: userId, reason: mergedReason)

        if listeners[userId] != nil {
            return
        }

        let ref = db.collection("public_lifetime_stats").document(userId)
        let registration = ref.addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                guard let self else { return }
                if userId == self.profileUserId {
                    self.profileInitialSnapshotReceivedForUserId = userId
                }
                if let error {
                    #if DEBUG
                    print("⚠️ public_lifetime_stats listener \(userId): \(error.localizedDescription)")
                    #endif
                    return
                }
                guard let snapshot else { return }
                let activeReason = self.listenerReason[userId] ?? reason
                self.applySnapshotDocument(userId: userId, snapshot: snapshot, reason: activeReason)
            }
        }
        listeners[userId] = registration
    }

    private func touchAccess(userId: String, reason: ListenerReason) {
        guard let ctx = modelContext else { return }
        let descriptor = FetchDescriptor<PublicLifetimeStatsCacheEntity>(
            predicate: #Predicate<PublicLifetimeStatsCacheEntity> { $0.userId == userId }
        )
        let now = Date()
        let familyPinnedRow = reason != .friend
        do {
            if let existing = try ctx.fetch(descriptor).first {
                existing.lastAccessedAt = now
                existing.isFamilyPinned = familyPinnedRow
                try ctx.save()
            }
        } catch {
            #if DEBUG
            print("⚠️ touchAccess public stats cache: \(error)")
            #endif
        }
    }

    private func applySnapshotDocument(userId: String, snapshot: DocumentSnapshot, reason: ListenerReason) {
        let now = Date()
        if !snapshot.exists {
            snapshots[userId] = nil
            return
        }
        guard let data = snapshot.data() else {
            snapshots[userId] = nil
            return
        }
        let trips = (data["totalCompletedTrips"] as? Int) ?? 0
        let games = (data["totalGamesPlayed"] as? Int) ?? 0
        let discoveries = (data["totalDiscoveries"] as? Int) ?? 0
        let score: Double = {
            if let d = data["totalWeightedScore"] as? Double { return d }
            if let n = data["totalWeightedScore"] as? NSNumber { return n.doubleValue }
            if let i = data["totalWeightedScore"] as? Int { return Double(i) }
            return 0
        }()
        let familyOnly = (data["familyOnlyTripsCount"] as? Int) ?? 0
        let friendsOnly = (data["friendsOnlyTripsCount"] as? Int) ?? 0
        let mixed = (data["mixedFriendsFamilyTripsCount"] as? Int) ?? 0
        let entireFamily = (data["entireFamilyTripsCount"] as? Int) ?? 0
        let lastComputed = (data["lastComputedAt"] as? Timestamp)?.dateValue() ?? now

        let stats = UserLifetimeStats(
            totalCompletedTrips: trips,
            totalGamesPlayed: games,
            totalDiscoveries: discoveries,
            totalWeightedScore: score,
            familyOnlyTripsCount: familyOnly,
            friendsOnlyTripsCount: friendsOnly,
            mixedFriendsFamilyTripsCount: mixed,
            entireFamilyTripsCount: entireFamily,
            lastComputedAt: lastComputed
        )
        snapshots[userId] = stats
        upsertCacheEntity(
            userId: userId,
            stats: stats,
            lastFetchedAt: now,
            reason: reason
        )
        AnalyticsService.shared.log(.publicLifetimeStatsListenerUpdated(userIdLength: userId.count))
    }

    private func upsertCacheEntity(
        userId: String,
        stats: UserLifetimeStats,
        lastFetchedAt: Date,
        reason: ListenerReason
    ) {
        guard let ctx = modelContext else { return }
        let descriptor = FetchDescriptor<PublicLifetimeStatsCacheEntity>(
            predicate: #Predicate<PublicLifetimeStatsCacheEntity> { $0.userId == userId }
        )
        do {
            let entity: PublicLifetimeStatsCacheEntity
            if let existing = try ctx.fetch(descriptor).first {
                entity = existing
            } else {
                entity = PublicLifetimeStatsCacheEntity(userId: userId)
                ctx.insert(entity)
            }
            entity.totalCompletedTrips = stats.totalCompletedTrips
            entity.totalGamesPlayed = stats.totalGamesPlayed
            entity.totalDiscoveries = stats.totalDiscoveries
            entity.totalWeightedScore = stats.totalWeightedScore
            entity.familyOnlyTripsCount = stats.familyOnlyTripsCount
            entity.friendsOnlyTripsCount = stats.friendsOnlyTripsCount
            entity.mixedFriendsFamilyTripsCount = stats.mixedFriendsFamilyTripsCount
            entity.entireFamilyTripsCount = stats.entireFamilyTripsCount
            entity.lastServerUpdatedAt = stats.lastComputedAt
            entity.lastFetchedAt = lastFetchedAt
            entity.isFamilyPinned = reason != .friend
            entity.lastAccessedAt = lastFetchedAt
            try ctx.save()
        } catch {
            #if DEBUG
            print("⚠️ upsert PublicLifetimeStatsCacheEntity: \(error)")
            #endif
        }
    }
}
