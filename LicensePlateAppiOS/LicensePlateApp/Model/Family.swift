//
//  Family.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import Foundation
import SwiftData

@Model
final class Family {
    @Attribute(.unique) var id: UUID
    var name: String? // Optional family name
    var createdAt: Date
    var lastUpdated: Date
    
    // Members (relationship to FamilyMember)
    @Relationship(deleteRule: .cascade, inverse: \FamilyMember.family)
    var members: [FamilyMember] = []
    
    // Linked families (for Retired Generals in multiple families)
    var linkedFamilyIDs: [UUID] = []
    
    // Limits (soft)
    var maxCaptains: Int = 2
    var maxScouts: Int = 3
    
    // Firebase sync
    var firebaseFamilyID: String?
    var needsSync: Bool = false
    
    // Share code for inviting members
    var shareCode: String? // For inviting members via share code
    
    init(
        id: UUID = UUID(),
        name: String? = nil,
        createdAt: Date = .now,
        lastUpdated: Date = .now,
        members: [FamilyMember] = [],
        linkedFamilyIDs: [UUID] = [],
        maxCaptains: Int = 2,
        maxScouts: Int = 3,
        firebaseFamilyID: String? = nil,
        needsSync: Bool = false,
        shareCode: String? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.lastUpdated = lastUpdated
        self.members = members
        self.linkedFamilyIDs = linkedFamilyIDs
        self.maxCaptains = maxCaptains
        self.maxScouts = maxScouts
        self.firebaseFamilyID = firebaseFamilyID
        self.needsSync = needsSync
        self.shareCode = shareCode
    }
    
    /// Generate a share code if one doesn't exist
    func generateShareCodeIfNeeded() {
        if shareCode == nil {
            shareCode = UUID().uuidString.prefix(8).uppercased()
        }
    }
    
    /// Regenerate the share code (overwrites existing code)
    func regenerateShareCode() {
        shareCode = UUID().uuidString.prefix(8).uppercased()
    }
    
    /// Get all members with a specific role
    func membersWithRole(_ role: FamilyMember.FamilyRole) -> [FamilyMember] {
        members.filter { $0.role == role && $0.isActive }
    }
    
    /// Get all active Captains
    var captains: [FamilyMember] {
        membersWithRole(.captain)
    }
    
    /// Get all active Sergeants
    var sergeants: [FamilyMember] {
        membersWithRole(.sergeant)
    }
    
    /// Get all active Scouts
    var scouts: [FamilyMember] {
        membersWithRole(.scout)
    }
    
    /// Get all active Retired Generals
    var retiredGenerals: [FamilyMember] {
        membersWithRole(.retiredGeneral)
    }
    
    /// Check if family is at or over limit for a role
    func isAtLimit(for role: FamilyMember.FamilyRole) -> Bool {
        switch role {
        case .captain:
            return captains.count >= maxCaptains
        case .scout:
            return scouts.count >= maxScouts
        case .sergeant, .retiredGeneral:
            return false // No limits for these roles
        }
    }
}

