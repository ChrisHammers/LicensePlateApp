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

    /// FR-86: identity the server stamps onto the pending row at creation, so a captain can
    /// tell two pending children apart *before* approving — FR-12 denies peer reads of a
    /// non-member child's user doc, so this is the only identity available pre-approval.
    ///
    /// `@Transient` is deliberate, not a shortcut: `PendingJoinRequest` is registered in the
    /// FROZEN V1 schema (`SchemaVersions.swift:25`), so adding *stored* properties would
    /// change V1's fingerprint — which CLAUDE.md forbids. These are safe to drop because
    /// pending rows are re-decoded from Firestore every time a family screen loads, and every
    /// consumer falls back to the generic placeholder when they are nil (so a cold-cache read
    /// renders exactly as it did before FR-86). Username and avatar ONLY — never contact
    /// fields; the server side is test-pinned against that.
    @Transient var userName: String?
    @Transient var avatarId: String?

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

        // FR-86 stamp. Absent on rows written before FR-86 and on any row the server did not
        // stamp; blank-normalised so an empty string never renders as an empty name.
        self.userName = Self.stampedValue(data["userName"])
        self.avatarId = Self.stampedValue(data["avatarId"])
    }

    /// Trims a stamped identity field and treats blank as absent, so consumers get a clean
    /// `nil` to fall back on rather than an empty label.
    private static func stampedValue(_ raw: Any?) -> String? {
        guard let value = raw as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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

