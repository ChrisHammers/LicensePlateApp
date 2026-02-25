//
//  Invite.swift
//  LicensePlateApp
//
//  Created for Friends & Family MVP
//

import Foundation
import SwiftData
import FirebaseFirestore

@Model
final class Invite {
    @Attribute(.unique) var inviteId: String
    var type: String // "friend" or "family"
    var fromUserId: String
    var toUserId: String?
    var familyId: String?
    var status: String // "pending", "accepted", "declined", "expired", "auto_rejected"
    var method: String // "search", "qr", "code", "deep_link"
    var codeId: String?
    var expiresAt: Date
    var createdAt: Date
    var respondedAt: Date?
    
    enum InviteType: String, Codable, CaseIterable {
        case friend
        case family
    }
    
    enum InviteStatus: String, Codable, CaseIterable {
        case pending
        case accepted
        case declined
        case expired
        case autoRejected = "auto_rejected"
    }
    
    enum InviteMethod: String, Codable, CaseIterable {
        case search
        case qr
        case code
        case deepLink = "deep_link"
    }
    
    init(
        inviteId: String,
        type: InviteType,
        fromUserId: String,
        toUserId: String? = nil,
        familyId: String? = nil,
        status: InviteStatus = .pending,
        method: InviteMethod,
        codeId: String? = nil,
        expiresAt: Date,
        createdAt: Date = .now,
        respondedAt: Date? = nil
    ) {
        self.inviteId = inviteId
        self.type = type.rawValue
        self.fromUserId = fromUserId
        self.toUserId = toUserId
        self.familyId = familyId
        self.status = status.rawValue
        self.method = method.rawValue
        self.codeId = codeId
        self.expiresAt = expiresAt
        self.createdAt = createdAt
        self.respondedAt = respondedAt
    }
    
    var isExpired: Bool {
        // Friend invites don't expire - only check expiration for family invites
        if typeEnum == .friend {
            return false
        }
        return expiresAt < Date()
    }
    
    /// Get type enum
    var typeEnum: InviteType {
        get {
            InviteType(rawValue: type) ?? .friend
        }
        set {
            type = newValue.rawValue
        }
    }
    
    /// Get status enum
    var statusEnum: InviteStatus {
        get {
            InviteStatus(rawValue: status) ?? .pending
        }
        set {
            status = newValue.rawValue
        }
    }
    
    /// Get method enum
    var methodEnum: InviteMethod {
        get {
            InviteMethod(rawValue: method) ?? .search
        }
        set {
            method = newValue.rawValue
        }
    }
}

// MARK: - Firestore Conversion

extension Invite {
    convenience init?(from document: DocumentSnapshot) {
        guard let data = document.data() else { return nil }
        self.init(from: data, id: document.documentID)
    }
    
    convenience init?(from data: [String: Any], id: String) {
        guard let typeString = data["type"] as? String,
              let type = InviteType(rawValue: typeString),
              let fromUserId = data["fromUserId"] as? String,
              let statusString = data["status"] as? String,
              let status = InviteStatus(rawValue: statusString),
              let methodString = data["method"] as? String,
              let method = InviteMethod(rawValue: methodString),
              let expiresAtTimestamp = data["expiresAt"] as? Timestamp,
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
            inviteId: id,
            type: type,
            fromUserId: fromUserId,
            toUserId: data["toUserId"] as? String,
            familyId: data["familyId"] as? String,
            status: status,
            method: method,
            codeId: data["codeId"] as? String,
            expiresAt: expiresAtTimestamp.dateValue(),
            createdAt: createdAtTimestamp.dateValue(),
            respondedAt: respondedAt
        )
    }
    
    func toFirestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "type": type,
            "fromUserId": fromUserId,
            "status": status,
            "method": method,
            "expiresAt": Timestamp(date: expiresAt),
            "createdAt": Timestamp(date: createdAt)
        ]
        
        if let toUserId = toUserId {
            data["toUserId"] = toUserId
        }
        
        if let familyId = familyId {
            data["familyId"] = familyId
        }
        
        if let codeId = codeId {
            data["codeId"] = codeId
        }
        
        if let respondedAt = respondedAt {
            data["respondedAt"] = Timestamp(date: respondedAt)
        }
        
        return data
    }
}
