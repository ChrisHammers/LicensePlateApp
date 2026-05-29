//
//  Friendship.swift
//  LicensePlateApp
//
//  Created for Friends & Family MVP
//

import Foundation
import SwiftData
import FirebaseFirestore

@Model
final class Friendship {
    @Attribute(.unique) var friendshipId: String
    var userA: String
    var userB: String
    var status: String // "accepted", "declined"
    var initiatedBy: String
    var createdAt: Date
    var respondedAt: Date?
    
    enum FriendshipStatus: String, Codable, CaseIterable {
        case accepted
        case declined
    }
    
    init(
        friendshipId: String,
        userA: String,
        userB: String,
        status: FriendshipStatus = .accepted,
        initiatedBy: String,
        createdAt: Date = .now,
        respondedAt: Date? = nil
    ) {
        self.friendshipId = friendshipId
        self.userA = userA
        self.userB = userB
        self.status = status.rawValue
        self.initiatedBy = initiatedBy
        self.createdAt = createdAt
        self.respondedAt = respondedAt
    }
    
    /// Generate stable friendship ID from two user IDs
    static func generateFriendshipId(userA: String, userB: String) -> String {
        let sorted = [userA, userB].sorted()
        return "\(sorted[0])_\(sorted[1])"
    }
    
    /// Check if a user is part of this friendship
    func contains(userId: String) -> Bool {
        userA == userId || userB == userId
    }
    
    /// Get the other user in the friendship
    func otherUser(than userId: String) -> String? {
        if userA == userId {
            return userB
        } else if userB == userId {
            return userA
        }
        return nil
    }
    
    /// Get status enum
    var statusEnum: FriendshipStatus {
        get {
            FriendshipStatus(rawValue: status) ?? .declined
        }
        set {
            status = newValue.rawValue
        }
    }
}

// MARK: - Firestore Conversion

extension Friendship {
    convenience init?(from document: DocumentSnapshot) {
        guard let data = document.data() else { return nil }
        self.init(from: data, id: document.documentID)
    }
    
    convenience init?(from data: [String: Any], id: String) {
        guard let userA = data["userA"] as? String,
              let userB = data["userB"] as? String,
              let statusString = data["status"] as? String,
              let status = FriendshipStatus(rawValue: statusString),
              let initiatedBy = data["initiatedBy"] as? String,
              let createdAtTimestamp = data["createdAt"] as? Timestamp else {
            return nil
        }
        
        let respondedAt: Date?
        if let respondedAtTimestamp = data["respondedAt"] as? Timestamp {
            respondedAt = respondedAtTimestamp.dateValue()
        } else {
            respondedAt = nil
        }
        
        self.init(
            friendshipId: id,
            userA: userA,
            userB: userB,
            status: status,
            initiatedBy: initiatedBy,
            createdAt: createdAtTimestamp.dateValue(),
            respondedAt: respondedAt
        )
    }
    
    func toFirestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "userA": userA,
            "userB": userB,
            "status": status,
            "initiatedBy": initiatedBy,
            "createdAt": Timestamp(date: createdAt)
        ]
        
        if let respondedAt = respondedAt {
            data["respondedAt"] = Timestamp(date: respondedAt)
        }
        
        return data
    }
}
