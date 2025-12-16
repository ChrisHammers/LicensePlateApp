//
//  ShareCode.swift
//  LicensePlateApp
//
//  Created for Friends & Family MVP
//

import Foundation
import SwiftData
import FirebaseFirestore

@Model
final class ShareCode {
    @Attribute(.unique) var codeId: String
    var type: String // "friend" or "family"
    var createdBy: String // User ID
    var familyId: String? // Only for family codes
    var code: String // Random code string
    var expiresAt: Date
    var createdAt: Date
    var isRevoked: Bool
    
    enum ShareCodeType: String, Codable, CaseIterable {
        case friend
        case family
    }
    
    init(
        codeId: String,
        type: ShareCodeType,
        createdBy: String,
        familyId: String? = nil,
        code: String,
        expiresAt: Date,
        createdAt: Date = .now,
        isRevoked: Bool = false
    ) {
        self.codeId = codeId
        self.type = type.rawValue
        self.createdBy = createdBy
        self.familyId = familyId
        self.code = code
        self.expiresAt = expiresAt
        self.createdAt = createdAt
        self.isRevoked = isRevoked
    }
    
    var isExpired: Bool {
        expiresAt < Date() || isRevoked
    }
    
    /// Get type enum
    var typeEnum: ShareCodeType {
        get {
            ShareCodeType(rawValue: type) ?? .friend
        }
        set {
            type = newValue.rawValue
        }
    }
}

// MARK: - Firestore Conversion

extension ShareCode {
    convenience init?(from document: DocumentSnapshot) {
        guard let data = document.data() else { return nil }
        self.init(from: data, id: document.documentID)
    }
    
    convenience init?(from data: [String: Any], id: String) {
        guard let typeString = data["type"] as? String,
              let type = ShareCodeType(rawValue: typeString),
              let createdBy = data["createdBy"] as? String,
              let code = data["code"] as? String,
              let expiresAtTimestamp = data["expiresAt"] as? Timestamp,
              let createdAtTimestamp = data["createdAt"] as? Timestamp else {
            return nil
        }
        
        self.init(
            codeId: id,
            type: type,
            createdBy: createdBy,
            familyId: data["familyId"] as? String,
            code: code,
            expiresAt: expiresAtTimestamp.dateValue(),
            createdAt: createdAtTimestamp.dateValue(),
            isRevoked: data["isRevoked"] as? Bool ?? false
        )
    }
    
    func toFirestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "type": type,
            "createdBy": createdBy,
            "code": code,
            "expiresAt": Timestamp(date: expiresAt),
            "createdAt": Timestamp(date: createdAt),
            "isRevoked": isRevoked
        ]
        
        if let familyId = familyId {
            data["familyId"] = familyId
        }
        
        return data
    }
}

