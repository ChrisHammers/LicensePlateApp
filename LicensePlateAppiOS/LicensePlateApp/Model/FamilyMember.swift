//
//  FamilyMember.swift
//  LicensePlateApp
//
//  Created for Friends & Family MVP
//

import Foundation
import SwiftData
import FirebaseFirestore

@Model
final class FamilyMember {
    @Attribute(.unique) var id: String // Composite: "familyId_userId" for SwiftData uniqueness
    var familyId: String
    @Attribute(.unique) var userId: String // User ID (document ID in Firestore members subcollection)
    var role: String // "creator", "captain", "sergeant", "scout", "retired_general"
    var canInvite: Bool
    var canEditSettings: Bool
    var joinedAt: Date
    var updatedAt: Date
    
    // Relationship to cached user data
    var user: AppUser?
    
    enum FamilyRole: String, Codable, CaseIterable {
        case creator
        case captain
        case sergeant
        case scout
        case retiredGeneral = "retired_general"
        
        var displayName: String {
            switch self {
            case .creator, .captain: return "Captain".localized
            case .sergeant: return "Sergeant".localized
            case .scout: return "Scout".localized
            case .retiredGeneral: return "Retired General".localized
            }
        }
    }
    
    init(
        familyId: String,
        userId: String,
        role: FamilyRole,
        canInvite: Bool = false,
        canEditSettings: Bool = false,
        joinedAt: Date = .now,
        updatedAt: Date = .now,
        user: AppUser? = nil
    ) {
        self.id = "\(familyId)_\(userId)"
        self.familyId = familyId
        self.userId = userId
        self.role = role.rawValue
        self.canInvite = canInvite
        self.canEditSettings = canEditSettings
        self.joinedAt = joinedAt
        self.updatedAt = updatedAt
        self.user = user
    }
    
    /// Get role enum
    var roleEnum: FamilyRole {
        get {
            FamilyRole(rawValue: role) ?? .scout
        }
        set {
            role = newValue.rawValue
            updatedAt = .now
        }
    }
    
    /// Check if member is captain or creator
    var isCaptainOrCreator: Bool {
        roleEnum == .captain || roleEnum == .creator
    }
}

// MARK: - Firestore Conversion

extension FamilyMember {
    convenience init?(from document: DocumentSnapshot, familyId: String) {
        guard let data = document.data() else { return nil }
        // Document ID is the userId in Firestore members subcollection
        self.init(from: data, userId: document.documentID, familyId: familyId)
    }
    
    convenience init?(from data: [String: Any], userId: String, familyId: String) {
        guard let roleString = data["role"] as? String,
              let role = FamilyRole(rawValue: roleString),
              let joinedAtTimestamp = data["joinedAt"] as? Timestamp else {
            return nil
        }
        
        let permissions = data["permissions"] as? [String: Any] ?? [:]
        let canInvite = permissions["canInvite"] as? Bool ?? false
        let canEditSettings = permissions["canEditSettings"] as? Bool ?? false
        
        let updatedAt: Date
        if let updatedAtTimestamp = data["updatedAt"] as? Timestamp {
            updatedAt = updatedAtTimestamp.dateValue()
        } else {
            updatedAt = joinedAtTimestamp.dateValue()
        }
        
        self.init(
            familyId: familyId,
            userId: userId, // userId is the document ID in Firestore
            role: role,
            canInvite: canInvite,
            canEditSettings: canEditSettings,
            joinedAt: joinedAtTimestamp.dateValue(),
            updatedAt: updatedAt
        )
    }
    
    func toFirestoreData() -> [String: Any] {
        [
            "role": role,
            "permissions": [
                "canInvite": canInvite,
                "canEditSettings": canEditSettings
            ],
            "joinedAt": Timestamp(date: joinedAt),
            "updatedAt": Timestamp(date: updatedAt)
        ]
    }
}

