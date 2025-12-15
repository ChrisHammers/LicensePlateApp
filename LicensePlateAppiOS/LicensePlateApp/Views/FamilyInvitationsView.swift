//
//  FamilyInvitationsView.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import SwiftUI
import SwiftData
import FirebaseFirestore

struct FamilyInvitationsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authService: FirebaseAuthService
    @Query(sort: \Family.createdAt, order: .reverse) private var allFamilies: [Family]
    
    @State private var pendingInvitations: [FamilyMember] = []
    @State private var isLoading = true
    @State private var memberUserNames: [String: String] = [:] // [userID: userName]
    @State private var familyNames: [UUID: String] = [:] // [familyID: familyName]
    @State private var familyFirebaseIDs: [UUID: String] = [:] // [familyID: firebaseFamilyID] - cache for looking up firebaseID
    
    var currentUser: AppUser? {
        authService.currentUser
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
                // Load pending invitations from Firestore FIRST
                if let userID = currentUser?.id {
                    print("🔍 DEBUG - FamilyInvitationsView loading invitations:")
                    print("   currentUser?.id: \(userID)")
                    print("   currentUser?.firebaseUID: \(currentUser?.firebaseUID ?? "nil")")
                    
                    do {
                        let firestoreInvitations = try await FirebaseFamilySyncService.shared.loadPendingInvitationsForUser(userID: userID)
                        print("🔍 DEBUG - FamilyInvitationsView received \(firestoreInvitations.count) invitations")
                        
                        // Build mapping of familyID -> firebaseFamilyID from user's pending invitations
                        let userRef = Firestore.firestore().collection("users").document(userID)
                        let userDoc = try? await userRef.getDocument()
                        if let data = userDoc?.data(),
                           let pendingInvitationsData = data["pendingFamilyInvitations"] as? [[String: Any]] {
                            for invitationData in pendingInvitationsData {
                                if let firebaseID = invitationData["familyFirebaseID"] as? String {
                                    // Get the family's localID to build the mapping
                                    let familyDoc = try? await Firestore.firestore()
                                        .collection("families")
                                        .document(firebaseID)
                                        .getDocument()
                                    if let familyData = familyDoc?.data(),
                                       let localIDString = familyData["localID"] as? String,
                                       let localID = UUID(uuidString: localIDString) {
                                        familyFirebaseIDs[localID] = firebaseID
                                    }
                                }
                            }
                        }
                        
                        // Store results in @State variable
                        pendingInvitations = firestoreInvitations.sorted { member1, member2 in
                            let date1 = member1.invitedAt ?? member1.joinedAt
                            let date2 = member2.invitedAt ?? member2.joinedAt
                            return date1 > date2
                        }
                    } catch {
                        print("❌ Error loading pending invitations: \(error)")
                        pendingInvitations = []
                    }
                } else {
                    print("❌ ERROR - No currentUser?.id in FamilyInvitationsView")
                    pendingInvitations = []
                }
                
                isLoading = false
                
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
        
        // CRITICAL: Ensure the invitation's userID matches the current user
        // This fixes the issue where the member's userID doesn't match
        if invitation.userID != currentUser.id {
            print("⚠️ WARNING - Invitation userID (\(invitation.userID)) doesn't match current user (\(currentUser.id)). Fixing...")
            invitation.userID = currentUser.id
        }
        
        // Accept the invitation - this sets invitationStatus to .accepted and isActive to true
        invitation.accept()
        
        // Explicitly ensure status is set correctly
        invitation.invitationStatus = .accepted
        invitation.isActive = true
        
        // Update user's familyID
        currentUser.familyID = invitation.familyID
        currentUser.needsSync = true
        
        // Remove from pending invitations list
        pendingInvitations.removeAll { $0.id == invitation.id }
        
        do {
            try modelContext.save()
            
            // Verify the status was saved
            print("🔍 DEBUG - After accept: invitationStatus = \(invitation.invitationStatus.rawValue), isActive = \(invitation.isActive)")
            
            // Sync to Firebase
            Task {
                do {
                    // Get firebaseFamilyID - try from cached mapping first, then invitation.family, then look up by local ID
                    var firebaseID: String?
                    
                    // First, try the cached mapping
                    if let cachedID = familyFirebaseIDs[invitation.familyID] {
                        firebaseID = cachedID
                        print("🔍 DEBUG - Found firebaseFamilyID from cache: \(firebaseID ?? "nil")")
                    } else if let family = invitation.family {
                        firebaseID = family.firebaseFamilyID
                        print("🔍 DEBUG - Found firebaseFamilyID from family relationship: \(firebaseID ?? "nil")")
                    } else {
                        // Family relationship not set, look it up by local ID
                        if let localFamily = try? await FirebaseFamilySyncService.shared.loadFamilyByLocalID(invitation.familyID) {
                            firebaseID = localFamily.firebaseFamilyID
                            print("🔍 DEBUG - Found firebaseFamilyID from loadFamilyByLocalID: \(firebaseID ?? "nil")")
                        } else {
                            print("❌ ERROR - Could not find firebaseFamilyID for invitation with familyID: \(invitation.familyID)")
                            print("   Cached mappings: \(familyFirebaseIDs)")
                            return
                        }
                    }
                    
                    guard let firebaseID = firebaseID else {
                        print("❌ ERROR - firebaseFamilyID is nil after all lookup attempts")
                        return
                    }
                    
                    // Save member with accepted status (this will call removePendingInvitationFromUserDocument)
                    try await FirebaseFamilySyncService.shared.saveFamilyMemberToFirestore(invitation, familyFirebaseID: firebaseID)
                    
                    // Also explicitly remove from user's pendingFamilyInvitations via Cloud Function
                    await FirebaseFamilySyncService.shared.removePendingInvitationFromUserDocument(
                        userID: currentUser.id,
                        familyFirebaseID: firebaseID
                    )
                    
                    // Save user data (familyID was updated, so needsSync should already be true)
                    currentUser.needsSync = true
                    try await authService.saveUserDataToFirestore(currentUser)
                    
                    // Load the family from Firestore to ensure it's up to date locally
                    if let loadedFamily = try? await FirebaseFamilySyncService.shared.loadFamilyFromFirestore(familyID: firebaseID) {
                        // Family loaded successfully
                        print("✅ Family loaded from Firestore: \(loadedFamily.id)")
                    } else {
                        // Try loading by local ID if firebaseID lookup fails
                        if let localFamily = try? await FirebaseFamilySyncService.shared.loadFamilyByLocalID(invitation.familyID) {
                            print("✅ Family loaded by local ID: \(localFamily.id)")
                        }
                    }
                    
                    // Reload invitations to refresh the list
                    await reloadInvitations()
                } catch {
                    print("Error syncing invitation acceptance: \(error)")
                }
            }
        } catch {
            print("Error accepting invitation: \(error)")
        }
    }
    
    private func reloadInvitations() async {
        guard let userID = currentUser?.id else { return }
        
        do {
            let firestoreInvitations = try await FirebaseFamilySyncService.shared.loadPendingInvitationsForUser(userID: userID)
            pendingInvitations = firestoreInvitations.sorted { member1, member2 in
                let date1 = member1.invitedAt ?? member1.joinedAt
                let date2 = member2.invitedAt ?? member2.joinedAt
                return date1 > date2
            }
        } catch {
            print("Error reloading invitations: \(error)")
        }
    }
    
    private func declineInvitation(_ invitation: FamilyMember) {
        guard let currentUser = currentUser else { return }
        
        // Decline the invitation - this sets invitationStatus to .declined and isActive to false
        invitation.decline()
        
        // Explicitly ensure status is set correctly
        invitation.invitationStatus = .declined
        invitation.isActive = false
        
        // Remove from pending invitations list
        pendingInvitations.removeAll { $0.id == invitation.id }
        
        do {
            try modelContext.save()
            
            // Verify the status was saved
            print("🔍 DEBUG - After decline: invitationStatus = \(invitation.invitationStatus.rawValue), isActive = \(invitation.isActive)")
            
            // Sync to Firebase
            Task {
                do {
                    // Get firebaseFamilyID - try from cached mapping first, then invitation.family, then look up by local ID
                    var firebaseID: String?
                    
                    // First, try the cached mapping
                    if let cachedID = familyFirebaseIDs[invitation.familyID] {
                        firebaseID = cachedID
                        print("🔍 DEBUG - Found firebaseFamilyID from cache: \(firebaseID ?? "nil")")
                    } else if let family = invitation.family {
                        firebaseID = family.firebaseFamilyID
                        print("🔍 DEBUG - Found firebaseFamilyID from family relationship: \(firebaseID ?? "nil")")
                    } else {
                        // Family relationship not set, look it up by local ID
                        if let localFamily = try? await FirebaseFamilySyncService.shared.loadFamilyByLocalID(invitation.familyID) {
                            firebaseID = localFamily.firebaseFamilyID
                            print("🔍 DEBUG - Found firebaseFamilyID from loadFamilyByLocalID: \(firebaseID ?? "nil")")
                        } else {
                            print("❌ ERROR - Could not find firebaseFamilyID for invitation with familyID: \(invitation.familyID)")
                            print("   Cached mappings: \(familyFirebaseIDs)")
                            return
                        }
                    }
                    
                    guard let firebaseID = firebaseID else {
                        print("❌ ERROR - firebaseFamilyID is nil after all lookup attempts")
                        return
                    }
                    
                    // Save member with declined status (this will call removePendingInvitationFromUserDocument)
                    try await FirebaseFamilySyncService.shared.saveFamilyMemberToFirestore(invitation, familyFirebaseID: firebaseID)
                    
                    // Also explicitly remove from user's pendingFamilyInvitations via Cloud Function
                    await FirebaseFamilySyncService.shared.removePendingInvitationFromUserDocument(
                        userID: currentUser.id,
                        familyFirebaseID: firebaseID
                    )
                    
                    // Reload invitations to refresh the list
                    await reloadInvitations()
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
              .buttonStyle(.plain)
                
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
              .buttonStyle(.plain)
                
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

