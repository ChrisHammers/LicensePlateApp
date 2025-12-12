//
//  FamilyInvitationsView.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import SwiftUI
import SwiftData

struct FamilyInvitationsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authService: FirebaseAuthService
    @Query(sort: \FamilyMember.invitedAt, order: .reverse) private var allFamilyMembers: [FamilyMember]
    @Query(sort: \Family.createdAt, order: .reverse) private var allFamilies: [Family]
    
    @State private var memberUserNames: [String: String] = [:] // [userID: userName]
    @State private var familyNames: [UUID: String] = [:] // [familyID: familyName]
    
    var currentUser: AppUser? {
        authService.currentUser
    }
    
    var pendingInvitations: [FamilyMember] {
        guard let userID = currentUser?.id else { return [] }
        return allFamilyMembers.filter { member in
            member.userID == userID && member.invitationStatus == .pending
        }
    }
    
    var body: some View {
        NavigationStack {
            AppBackgroundView {
                if pendingInvitations.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "envelope.open.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        
                        Text("No Pending Invitations".localized)
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("You don't have any pending family invitations.".localized)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding()
                } else {
                    List {
                        Section("Pending Invitations".localized) {
                            ForEach(pendingInvitations) { invitation in
                                FamilyInvitationRow(invitation: invitation) {
                                    acceptInvitation(invitation)
                                } onDecline: {
                                    declineInvitation(invitation)
                                }
                            }
                        }
                        .textCase(nil)
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Family Invitations".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done".localized)
                    }
                }
            }
            .task {
                // Load pending invitations from Firestore if online
                if let userID = currentUser?.id {
                    do {
                        let firestoreInvitations = try await FirebaseFamilySyncService.shared.loadPendingInvitationsForUser(userID: userID)
                        // The method already saves to local SwiftData, so pendingInvitations computed property will pick them up
                    } catch {
                        print("Error loading pending invitations: \(error)")
                    }
                }
                
                // Pre-fetch userNames and family names
                let inviterIDs = pendingInvitations.compactMap { $0.invitedBy }
                let familyIDs = pendingInvitations.map { $0.familyID }
                
                // Fetch userNames
                if !inviterIDs.isEmpty {
                    memberUserNames = await UserLookupHelper.getUserNames(for: inviterIDs, in: modelContext)
                }
                
                // Fetch family names
                for familyID in familyIDs {
                    if let family = allFamilies.first(where: { $0.id == familyID }) {
                        familyNames[familyID] = family.name
                    }
                }
            }
        }
    }
    
    private func acceptInvitation(_ invitation: FamilyMember) {
        guard let currentUser = currentUser else { return }
        
        // Accept the invitation
        invitation.accept()
        
        // Update user's familyID
        currentUser.familyID = invitation.familyID
        currentUser.needsSync = true
        
        do {
            try modelContext.save()
            
            // Sync to Firebase
            Task {
                do {
                    if let family = invitation.family,
                       let firebaseID = family.firebaseFamilyID {
                        try await FirebaseFamilySyncService.shared.saveFamilyMemberToFirestore(invitation, familyFirebaseID: firebaseID)
                        try await authService.saveUserDataToFirestore(currentUser)
                    }
                } catch {
                    print("Error syncing invitation acceptance: \(error)")
                }
            }
        } catch {
            print("Error accepting invitation: \(error)")
        }
    }
    
    private func declineInvitation(_ invitation: FamilyMember) {
        // Decline the invitation
        invitation.decline()
        
        do {
            try modelContext.save()
            
            // Sync to Firebase
            Task {
                do {
                    if let family = invitation.family,
                       let firebaseID = family.firebaseFamilyID {
                        try await FirebaseFamilySyncService.shared.saveFamilyMemberToFirestore(invitation, familyFirebaseID: firebaseID)
                    }
                } catch {
                    print("Error syncing invitation decline: \(error)")
                }
            }
        } catch {
            print("Error declining invitation: \(error)")
        }
    }
}

struct FamilyInvitationRow: View {
    let invitation: FamilyMember
    let onAccept: () -> Void
    let onDecline: () -> Void
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Family.createdAt, order: .reverse) private var allFamilies: [Family]
    
    @State private var inviterName: String = "Unknown User".localized
    @State private var familyName: String = "Family".localized
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(familyName)
                        .font(.headline)
                    
                    if let invitedAt = invitation.invitedAt {
                        HStack(spacing: 4) {
                            Text("Invited".localized)
                            Text(invitedAt, style: .relative)
                            Text("by \(inviterName)".localized)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    } else {
                        Text("Invited by \(inviterName)".localized)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    Text("Role: \(invitation.role.displayName)".localized)
                        .font(.caption)
                        .foregroundStyle(Color.Theme.primaryBlue)
                }
                
                Spacer()
            }
            
            HStack(spacing: 12) {
                Button {
                    onAccept()
                } label: {
                    Text("Accept".localized)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.green)
                        .cornerRadius(8)
                }
                
                Button {
                    onDecline()
                } label: {
                    Text("Decline".localized)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.red)
                        .cornerRadius(8)
                }
            }
        }
        .padding(.vertical, 4)
        .task {
            // Fetch inviter name
            if let invitedBy = invitation.invitedBy {
                if let userName = await UserLookupHelper.getUserName(for: invitedBy, in: modelContext) {
                    inviterName = userName
                }
            }
            
            // Fetch family name
            if let family = allFamilies.first(where: { $0.id == invitation.familyID }) {
                familyName = family.name ?? "Family".localized
            }
        }
    }
}

