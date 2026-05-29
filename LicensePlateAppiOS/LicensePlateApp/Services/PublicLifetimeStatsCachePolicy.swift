//
//  PublicLifetimeStatsCachePolicy.swift
//  LicensePlateApp
//
//  Pure policy: LRU eviction for friend listeners (family + profile stay pinned).
//

import Foundation

enum PublicLifetimeStatsCachePolicy {
    /// Max concurrent Firestore listeners for non-pinned users (friends scrolling in UI).
    static let maxFriendListeners = 50

    /// Picks friend listener userIds to remove so a new friend observation can be added without exceeding the cap.
    /// - Parameters:
    ///   - observedFriendIds: User IDs currently listened to as friends (not profile, not family).
    ///   - accessRecords: `(userId, lastAccessedAt)` for those friends (typically from SwiftData cache rows).
    ///   - incomingUserId: Friend about to be observed; never evicted by this call.
    static func friendUserIdsToEvict(
        observedFriendIds: Set<String>,
        accessRecords: [(userId: String, lastAccessedAt: Date)],
        incomingUserId: String
    ) -> [String] {
        if observedFriendIds.contains(incomingUserId) {
            return []
        }
        let over = observedFriendIds.count - maxFriendListeners + 1
        if over <= 0 {
            return []
        }
        let accessById = Dictionary(uniqueKeysWithValues: accessRecords.map { ($0.userId, $0.lastAccessedAt) })
        let victims = observedFriendIds
            .filter { $0 != incomingUserId }
            .sorted { a, b in
                let da = accessById[a] ?? .distantPast
                let db = accessById[b] ?? .distantPast
                if da != db { return da < db }
                return a < b
            }
        return Array(victims.prefix(over))
    }
}
