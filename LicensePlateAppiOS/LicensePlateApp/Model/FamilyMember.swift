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
    var isActive: Bool = true
    
    // Relationship to Family
    var family: Family?
    
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
        isActive: Bool = true
    ) {
        self.id = id
        self.userID = userID
        self.familyID = familyID
        self.role = role
        self.joinedAt = joinedAt
        self.invitedBy = invitedBy
        self.isActive = isActive
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

