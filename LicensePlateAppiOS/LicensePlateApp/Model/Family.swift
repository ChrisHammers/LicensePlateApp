//
//  Family.swift
//  LicensePlateApp
//
//  Created for Friends & Family MVP
//

import Foundation
import SwiftData
import FirebaseFirestore

@Model
final class Family {
    @Attribute(.unique) var familyId: String
    var name: String
    var creatorId: String
    var status: String // "active" or "inactive"
    var createdAt: Date
    var updatedAt: Date
    
    enum FamilyStatus: String, Codable, CaseIterable {
        case active
        case inactive
    }
    
    init(
        familyId: String,
        name: String,
        creatorId: String,
        status: FamilyStatus = .active,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.familyId = familyId
        self.name = name
        self.creatorId = creatorId
        self.status = status.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    /// Get status enum
    var statusEnum: FamilyStatus {
        get {
            FamilyStatus(rawValue: status) ?? .active
        }
        set {
            status = newValue.rawValue
            updatedAt = .now
        }
    }
}

// MARK: - Firestore Conversion

extension Family {
    convenience init?(from document: DocumentSnapshot) {
        guard let data = document.data() else { return nil }
        self.init(from: data, id: document.documentID)
    }
    
    convenience init?(from data: [String: Any], id: String) {
        guard let name = data["name"] as? String,
              let creatorId = data["creatorId"] as? String,
              let statusString = data["status"] as? String,
              let status = FamilyStatus(rawValue: statusString),
              let createdAtTimestamp = data["createdAt"] as? Timestamp,
              let updatedAtTimestamp = data["updatedAt"] as? Timestamp else {
            return nil
        }
        
        self.init(
            familyId: id,
            name: name,
            creatorId: creatorId,
            status: status,
            createdAt: createdAtTimestamp.dateValue(),
            updatedAt: updatedAtTimestamp.dateValue()
        )
    }
    
    func toFirestoreData() -> [String: Any] {
        [
            "name": name,
            "creatorId": creatorId,
            "status": status,
            "createdAt": Timestamp(date: createdAt),
            "updatedAt": Timestamp(date: updatedAt)
        ]
    }
}

