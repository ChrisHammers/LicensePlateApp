//
//  PendingJoinRequest.swift
//  LicensePlateApp
//
//  Created for Friends & Family MVP
//

import Foundation
import SwiftData
import FirebaseFirestore

@Model
final class PendingJoinRequest {
    @Attribute(.unique) var requestId: String
    var familyId: String
    var userId: String
    var requestedBy: String // User ID who sent the invite
    var method: String // "search", "qr", "code", "deep_link"
    var status: String // "pending", "approved", "declined", "expired"
    var createdAt: Date
    var resolvedAt: Date?
    
    // Relationship to cached user data
    var user: AppUser?
    
    enum RequestStatus: String, Codable, CaseIterable {
        case pending
        case approved
        case declined
        case expired
    }
    
    enum RequestMethod: String, Codable, CaseIterable {
        case search
        case qr
        case code
        case deepLink = "deep_link"
    }
    
    init(
        requestId: String,
        familyId: String,
        userId: String,
        requestedBy: String,
        method: RequestMethod,
        status: RequestStatus = .pending,
        createdAt: Date = .now,
        resolvedAt: Date? = nil,
        user: AppUser? = nil
    ) {
        self.requestId = requestId
        self.familyId = familyId
        self.userId = userId
        self.requestedBy = requestedBy
        self.method = method.rawValue
        self.status = status.rawValue
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
        self.user = user
    }
    
    /// Get status enum
    var statusEnum: RequestStatus {
        get {
            RequestStatus(rawValue: status) ?? .pending
        }
        set {
            status = newValue.rawValue
            if newValue != .pending {
                resolvedAt = .now
            }
        }
    }
    
    /// Get method enum
    var methodEnum: RequestMethod {
        get {
            RequestMethod(rawValue: method) ?? .search
        }
        set {
            method = newValue.rawValue
        }
    }
}

// MARK: - Firestore Conversion

extension PendingJoinRequest {
    convenience init?(from document: DocumentSnapshot, familyId: String) {
        guard let data = document.data() else { return nil }
        self.init(from: data, id: document.documentID, familyId: familyId)
    }
    
    convenience init?(from data: [String: Any], id: String, familyId: String) {
        guard let userId = data["userId"] as? String,
              let requestedBy = data["requestedBy"] as? String,
              let methodString = data["method"] as? String,
              let method = RequestMethod(rawValue: methodString),
              let statusString = data["status"] as? String,
              let status = RequestStatus(rawValue: statusString),
              let createdAtTimestamp = data["createdAt"] as? Timestamp else {
            return nil
        }
        
        let resolvedAt: Date?
        if let resolvedAtTimestamp = data["resolvedAt"] as? Timestamp {
            resolvedAt = resolvedAtTimestamp.dateValue()
        } else {
            resolvedAt = nil
        }
        
        self.init(
            requestId: id,
            familyId: familyId,
            userId: userId,
            requestedBy: requestedBy,
            method: method,
            status: status,
            createdAt: createdAtTimestamp.dateValue(),
            resolvedAt: resolvedAt
        )
    }
    
    func toFirestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "userId": userId,
            "requestedBy": requestedBy,
            "method": method,
            "status": status,
            "createdAt": Timestamp(date: createdAt)
        ]
        
        if let resolvedAt = resolvedAt {
            data["resolvedAt"] = Timestamp(date: resolvedAt)
        }
        
        return data
    }
}

