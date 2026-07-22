//
//  FriendUserIdsRepository.swift
//  LicensePlateApp
//
//  SwiftData read: accepted friend peer user ids for lifetime stats classification.
//

import Foundation
import SwiftData

enum FriendUserIdsRepositoryError: Error, LocalizedError {
    case noModelContext

    var errorDescription: String? {
        switch self {
        case .noModelContext: return "error.friend_lookup_no_context".localized
        }
    }
}

@MainActor
final class FriendUserIdsRepository {
    static let shared = FriendUserIdsRepository()

    private var modelContext: ModelContext?

    private init() {}

    func setModelContext(_ context: ModelContext) {
        modelContext = context
    }

    /// Peer `userId` values from accepted friendships for the subject, or empty if none.
    func activeFriendUserIds(forAppUserId userId: String) throws -> Set<String> {
        guard modelContext != nil else { throw FriendUserIdsRepositoryError.noModelContext }
        let friendships = FriendshipRepository.shared.getAcceptedFriendships(for: userId)
        var peers = Set<String>()
        for friendship in friendships {
            if let other = friendship.otherUser(than: userId) {
                peers.insert(other)
            }
        }
        return peers
    }
}
