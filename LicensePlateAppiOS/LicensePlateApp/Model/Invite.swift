//
//  Invite.swift
//  LicensePlateApp
//
//  Created for Friends & Family MVP
//

import Foundation
import SwiftData
import FirebaseFirestore

/// Denormalized captain/creator row stamped on family invites for invitee UI.
struct FamilyInviteCaptainPreview: Equatable, Codable, Identifiable {
    var displayName: String
    var userName: String
    var role: String // "creator" | "captain"
    var avatarId: String?
    var userId: String?

    var id: String { "\(userId ?? userName)-\(role)-\(displayName)" }

    var isCreator: Bool { role == "creator" }
}

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

    // Family invite display snapshot (optional; older invites omit these)
    var familyName: String?
    var creatorDisplayName: String?
    var creatorUserName: String?
    var creatorAvatarId: String?
    var fromUserDisplayName: String?
    var fromUserUserName: String?
    var fromUserAvatarId: String?
    var captainsPreviewJSON: String?
    
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
        respondedAt: Date? = nil,
        familyName: String? = nil,
        creatorDisplayName: String? = nil,
        creatorUserName: String? = nil,
        creatorAvatarId: String? = nil,
        fromUserDisplayName: String? = nil,
        fromUserUserName: String? = nil,
        fromUserAvatarId: String? = nil,
        captainsPreviewJSON: String? = nil
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
        self.familyName = familyName
        self.creatorDisplayName = creatorDisplayName
        self.creatorUserName = creatorUserName
        self.creatorAvatarId = creatorAvatarId
        self.fromUserDisplayName = fromUserDisplayName
        self.fromUserUserName = fromUserUserName
        self.fromUserAvatarId = fromUserAvatarId
        self.captainsPreviewJSON = captainsPreviewJSON
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

    /// Decoded captains/creator preview for family invite UI.
    var captainsPreview: [FamilyInviteCaptainPreview] {
        Self.decodeCaptainsPreview(from: captainsPreviewJSON)
    }

    static func decodeCaptainsPreview(from json: String?) -> [FamilyInviteCaptainPreview] {
        guard let json, let data = json.data(using: .utf8) else { return [] }
        if let decoded = try? JSONDecoder().decode([FamilyInviteCaptainPreview].self, from: data) {
            return decoded
        }
        // Defensive fallback when null avatarId / mixed types trip Codable
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return raw.compactMap { Self.captainPreview(from: $0) }
    }

    static func captainPreview(from dict: [String: Any]) -> FamilyInviteCaptainPreview? {
        guard let displayName = dict["displayName"] as? String,
              let role = dict["role"] as? String else { return nil }
        let userName = dict["userName"] as? String ?? ""
        let avatarId = dict["avatarId"] as? String
        let userId = dict["userId"] as? String
        return FamilyInviteCaptainPreview(
            displayName: displayName,
            userName: userName,
            role: role,
            avatarId: (avatarId?.isEmpty == false) ? avatarId : nil,
            userId: (userId?.isEmpty == false) ? userId : nil
        )
    }

    static func encodeCaptainsPreview(_ captains: [FamilyInviteCaptainPreview]) -> String? {
        guard let data = try? JSONEncoder().encode(captains) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func captainsPreviewJSON(fromFirestoreCaptainsPreview value: Any?) -> String? {
        if let json = value as? String {
            return json
        }
        guard let array = value as? [Any] else { return nil }
        let captains: [FamilyInviteCaptainPreview] = array.compactMap { item in
            guard let dict = item as? [String: Any] else { return nil }
            return captainPreview(from: dict)
        }
        return encodeCaptainsPreview(captains)
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

        // Server may store captains as JSON string or as a native array
        let captainsPreviewJSON = Self.captainsPreviewJSON(
            fromFirestoreCaptainsPreview: data["captainsPreviewJSON"] ?? data["captainsPreview"]
        )
        
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
            respondedAt: respondedAt,
            familyName: data["familyName"] as? String,
            creatorDisplayName: data["creatorDisplayName"] as? String,
            creatorUserName: data["creatorUserName"] as? String,
            creatorAvatarId: data["creatorAvatarId"] as? String,
            fromUserDisplayName: data["fromUserDisplayName"] as? String,
            fromUserUserName: data["fromUserUserName"] as? String,
            fromUserAvatarId: data["fromUserAvatarId"] as? String,
            captainsPreviewJSON: captainsPreviewJSON
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

        if let familyName = familyName {
            data["familyName"] = familyName
        }
        if let creatorDisplayName = creatorDisplayName {
            data["creatorDisplayName"] = creatorDisplayName
        }
        if let creatorUserName = creatorUserName {
            data["creatorUserName"] = creatorUserName
        }
        if let creatorAvatarId = creatorAvatarId {
            data["creatorAvatarId"] = creatorAvatarId
        }
        if let fromUserDisplayName = fromUserDisplayName {
            data["fromUserDisplayName"] = fromUserDisplayName
        }
        if let fromUserUserName = fromUserUserName {
            data["fromUserUserName"] = fromUserUserName
        }
        if let fromUserAvatarId = fromUserAvatarId {
            data["fromUserAvatarId"] = fromUserAvatarId
        }
        if let captainsPreviewJSON = captainsPreviewJSON {
            data["captainsPreviewJSON"] = captainsPreviewJSON
        }
        
        return data
    }
}
