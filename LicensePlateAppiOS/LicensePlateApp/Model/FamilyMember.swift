//
//  FamilyMember.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import Foundation
import SwiftData

@Model
final class FamilyMember {
    @Attribute(.unique) var id: UUID
    var userID: String // Reference to AppUser.id
    var familyID: UUID // Reference to Family.id
    var role: FamilyRole
    var joinedAt: Date
    var invitedBy: String? // User ID who invited them
    var isActive: Bool
    var invitationStatus: InvitationStatus
    var invitedAt: Date? // When invitation was sent (nil if not invited)
    
    // Relationship to Family
    var family: Family?
    
    enum InvitationStatus: String, Codable {
        case pending
        case accepted
        case declined
    }
    
    enum FamilyRole: String, Codable, CaseIterable {
        case captain
        case sergeant
        case scout
        case retiredGeneral
        
        var displayName: String {
            switch self {
            case .captain: return "Captain"
            case .sergeant: return "Sergeant"
            case .scout: return "Scout"
            case .retiredGeneral: return "Retired General"
            }
        }
    }
    
    init(
        id: UUID = UUID(),
        userID: String,
        familyID: UUID,
        role: FamilyRole,
        joinedAt: Date = .now,
        invitedBy: String? = nil,
        isActive: Bool = true,
        invitationStatus: InvitationStatus = .pending,
        invitedAt: Date? = nil
    ) {
        self.id = id
        self.userID = userID
        self.familyID = familyID
        self.role = role
        self.joinedAt = joinedAt
        self.invitedBy = invitedBy
        self.isActive = isActive
        self.invitationStatus = invitationStatus
        self.invitedAt = invitedAt
    }
    
    /// Initialize with default accepted status (for backward compatibility)
    convenience init(
        id: UUID = UUID(),
        userID: String,
        familyID: UUID,
        role: FamilyRole,
        joinedAt: Date = .now,
        invitedBy: String? = nil,
        isActive: Bool = true
    ) {
        self.init(
            id: id,
            userID: userID,
            familyID: familyID,
            role: role,
            joinedAt: joinedAt,
            invitedBy: invitedBy,
            isActive: isActive,
            invitationStatus: .pending,
            invitedAt: nil
        )
    }
    
    /// Accept the family invitation
    func accept() {
        self.invitationStatus = .accepted
        self.isActive = true
        self.joinedAt = .now
    }
    
    /// Decline the family invitation
    func decline() {
        self.invitationStatus = .declined
        self.isActive = false
    }
    
    /// Check if member has permission to perform an action
    func canPerformAction(_ action: MemberAction) -> Bool {
        switch action {
        case .manageFamily:
            return role == .captain
        case .approveFriendRequests:
            return role == .captain
        case .createTrips:
            return role != .scout
        case .modifyTripSettings:
            return role != .scout
        case .markPlates:
            return true // All roles can mark plates
        case .inviteToFamily:
            return role == .captain
        case .removeMembers:
            return role == .captain
        }
    }
    
    enum MemberAction {
        case manageFamily
        case approveFriendRequests
        case createTrips
        case modifyTripSettings
        case markPlates
        case inviteToFamily
        case removeMembers
    }
}

