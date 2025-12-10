//
//  FriendRequest.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import Foundation
import SwiftData

@Model
final class FriendRequest {
    @Attribute(.unique) var id: UUID
    var fromUserID: String
    var toUserID: String
    var status: FriendRequestStatus
    var createdAt: Date
    var respondedAt: Date?
    var approvedBy: String? // Captain ID if Scout needed approval
    
    enum FriendRequestStatus: String, Codable, CaseIterable {
        case pending
        case approved
        case denied
        case requiresCaptainApproval // For Scout friend requests
        
        var displayName: String {
            switch self {
            case .pending: return "Pending"
            case .approved: return "Approved"
            case .denied: return "Denied"
            case .requiresCaptainApproval: return "Requires Approval"
            }
        }
    }
    
    init(
        id: UUID = UUID(),
        fromUserID: String,
        toUserID: String,
        status: FriendRequestStatus = .pending,
        createdAt: Date = .now,
        respondedAt: Date? = nil,
        approvedBy: String? = nil
    ) {
        self.id = id
        self.fromUserID = fromUserID
        self.toUserID = toUserID
        self.status = status
        self.createdAt = createdAt
        self.respondedAt = respondedAt
        self.approvedBy = approvedBy
    }
    
    /// Approve the friend request
    func approve(by captainID: String? = nil) {
        status = .approved
        respondedAt = .now
        if let captainID = captainID {
            approvedBy = captainID
        }
    }
    
    /// Deny the friend request
    func deny() {
        status = .denied
        respondedAt = .now
    }
    
    /// Check if request is still pending
    var isPending: Bool {
        status == .pending || status == .requiresCaptainApproval
    }
}

