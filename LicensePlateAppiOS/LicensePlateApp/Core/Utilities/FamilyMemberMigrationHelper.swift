//
//  FamilyMemberMigrationHelper.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import Foundation
import SwiftData

/// Helper to migrate and fix FamilyMember records with invalid invitationStatus values
enum FamilyMemberMigrationHelper {
    /// Fix any FamilyMember records with invalid invitationStatus values
    /// This should be called on app startup to fix any corrupted data
    /// Note: This can't fix records that crash during SwiftData decoding,
    /// but it can fix records that have invalid enum values after decoding
    static func fixInvalidInvitationStatus(in modelContext: ModelContext) {
        // Use a predicate-less fetch to get all members
        // If this crashes, the data is too corrupted and needs to be reloaded from Firestore
        let descriptor = FetchDescriptor<FamilyMember>()
        
        do {
            let allMembers = try modelContext.fetch(descriptor)
            var fixedCount = 0
            
            for member in allMembers {
                // Check if invitationStatus is valid
                // If accessing it crashes, we can't fix it here (would need to reload from Firestore)
                let currentStatus = member.invitationStatus
                
                // Verify it's a valid enum case
                var needsFix = false
                var newStatus: FamilyMember.InvitationStatus = .accepted
                
                switch currentStatus {
                case .pending, .accepted, .declined:
                    // Valid status, no fix needed
                    break
                @unknown default:
                    // Unknown case, needs fix
                    needsFix = true
                    newStatus = member.isActive ? .accepted : .pending
                }
                
                if needsFix {
                    member.invitationStatus = newStatus
                    fixedCount += 1
                }
            }
            
            if fixedCount > 0 {
                try modelContext.save()
                print("✅ Fixed \(fixedCount) FamilyMember records with invalid invitationStatus")
            }
        } catch {
            // If fetching itself fails, the data is corrupted at the SwiftData level
            // The only way to fix this is to delete the corrupted records and reload from Firestore
            print("⚠️ Error fetching FamilyMember records for migration: \(error)")
            print("⚠️ Corrupted records detected. Consider reloading family data from Firestore.")
        }
    }
}

