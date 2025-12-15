//
//  FamilyHubView.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import SwiftUI
import SwiftData
import FirebaseFirestore

struct FamilyHubView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authService: FirebaseAuthService
    @Query(sort: \Family.createdAt, order: .reverse) private var families: [Family]
    @Query(sort: \Trip.createdAt, order: .reverse) private var allTrips: [Trip]
    @Query(sort: \Game.createdAt, order: .reverse) private var allGames: [Game]
    // Use a safer query that won't crash on invalid data
    // We'll fetch manually to handle errors gracefully
    @State private var allFamilyMembers: [FamilyMember] = []
    
    @State private var selectedFamily: Family?
    @State private var showFamilySettings = false
    @State private var showInviteFamily = false
    @State private var showFamilyInvitations = false
    @State private var navigationPath: [NavigationDestination] = []
    @State private var memberUserNames: [String: String] = [:] // [userID: userName] - pre-fetched for cache population
    @State private var hasMigrationError = false
    @State private var familyListener: ListenerRegistration?
    
    enum NavigationDestination: Hashable {
        case trip(UUID)
        case game(UUID)
    }
    
    var currentUser: AppUser? {
        authService.currentUser
    }
    
    var currentFamily: Family? {
        print("🔍 DEBUG - currentFamily: Checking...")
        print("   currentUser: \(currentUser != nil ? "exists" : "nil")")
        print("   currentUser?.id: \(currentUser?.id ?? "nil")")
        print("   currentUser?.familyID: \(currentUser?.familyID?.uuidString ?? "nil")")
        
        guard let userID = currentUser?.id,
              let familyID = currentUser?.familyID else {
            print("🔍 DEBUG - currentFamily: No userID or familyID")
            if currentUser == nil {
                print("   Reason: currentUser is nil")
            } else if currentUser?.id == nil {
                print("   Reason: currentUser.id is nil")
            } else if currentUser?.familyID == nil {
                print("   Reason: currentUser.familyID is nil")
            }
            return nil
        }
        print("🔍 DEBUG - currentFamily: Looking for familyID: \(familyID)")
        print("🔍 DEBUG - currentFamily: Available families: \(families.map { $0.id })")
        
        guard let family = families.first(where: { $0.id == familyID }) else {
            print("⚠️ DEBUG - currentFamily: Family not found locally with id: \(familyID)")
            return nil
        }
        
        // Validate user is actually an active, accepted member
        let isMember = family.members.contains { member in
            member.userID == userID && 
            member.isActive && 
            member.invitationStatus == .accepted
        }
        
        print("🔍 DEBUG - currentFamily: isMember: \(isMember), family.members.count: \(family.members.count)")
        if !isMember {
            print("🔍 DEBUG - currentFamily: Member details:")
            for member in family.members {
                print("   - userID: \(member.userID), isActive: \(member.isActive), invitationStatus: \(member.invitationStatus.rawValue)")
            }
        }
        
        return isMember ? family : nil
    }
    
    var pendingInvitationsCount: Int {
        guard let userID = currentUser?.id else { return 0 }
        print ("Found USerID: \(userID), ")
        return allFamilyMembers.filter { member in
            member.userID == userID && safeInvitationStatus(for: member) == .pending
        }.count
    }
    
    /// Safely get family members, filtering out any that cause crashes
    private func safeFamilyMembers(_ family: Family) -> [FamilyMember] {
        // Try to access family.members - if it crashes due to corrupted data,
        // we'll catch it and return an empty array
        do {
            // Access the members relationship
            let members = family.members
            // Try to access each member's invitationStatus to filter out corrupted ones
            return members.filter { member in
                do {
                    _ = member.invitationStatus.rawValue
                    return true
                } catch {
                    // This member has corrupted data, skip it
                    return false
                }
            }
        } catch {
            // If accessing family.members itself crashes, return empty array
            print("⚠️ Error accessing family.members: \(error)")
            return []
        }
    }
    
    /// Safely get invitation status, handling invalid values
    private func safeInvitationStatus(for member: FamilyMember) -> FamilyMember.InvitationStatus {
        // Try to access the status - if it crashes, return a default
        // Note: This won't catch SwiftData decoding errors, but will handle runtime access issues
        let status = member.invitationStatus
        // Verify it's a valid case
        switch status {
        case .pending, .accepted, .declined:
            return status
        @unknown default:
            return member.isActive ? .accepted : .pending
        }
    }
    
    /// Load family members manually to handle errors gracefully
    private func loadFamilyMembers() async {
        do {
            let descriptor = FetchDescriptor<FamilyMember>(
                sortBy: [SortDescriptor(\FamilyMember.invitedAt, order: .reverse)]
            )
            let members = try modelContext.fetch(descriptor)
            allFamilyMembers = members
        } catch {
            print("⚠️ Error loading family members: \(error)")
            hasMigrationError = true
            allFamilyMembers = []
        }
    }
    
    private func removePendingInvitation(_ member: FamilyMember) {
        guard let firebaseFamilyID = currentFamily?.firebaseFamilyID else { return }
        
        Task {
            do {
                try await FirebaseFamilySyncService.shared.removePendingInvitation(
                    userID: member.userID,
                    familyFirebaseID: firebaseFamilyID
                )
                // Reload family members
                await loadFamilyMembers()
            } catch {
                print("Error removing pending invitation: \(error)")
            }
        }
    }
    
    var sharedTrips: [Trip] {
        guard let familyID = currentFamily?.id else { return [] }
        return allTrips.filter { trip in
            trip.isShared && (trip.sharedWithFamilyID == familyID || trip.sharedWithUserIDs.contains(currentUser?.id ?? ""))
        }
    }
    
    var activeGames: [Game] {
        guard let familyID = currentFamily?.id else { return [] }
        return allGames.filter { game in
            game.isActive && game.teams.contains { team in
                team.allMemberIDs.contains(currentUser?.id ?? "")
            }
        }
    }
    
    var body: some View {
        AppBackgroundView {
            if let family = currentFamily {
                    List {
                        // Family Overview Section
                        Section {
                            familyOverview(family: family)
                        }
                        .textCase(nil)
                        
                        // Active Shared Trips
                        if !sharedTrips.isEmpty {
                            Section("Active Shared Trips".localized) {
                                ForEach(sharedTrips.prefix(5)) { trip in
                                    NavigationLink(value: NavigationDestination.trip(trip.id)) {
                                        PublicTripRow(trip: trip)
                                    }
                                }
                            }
                            .textCase(nil)
                        }
                        
                        // Active Games
                        if !activeGames.isEmpty {
                            Section("Active Games".localized) {
                                ForEach(activeGames.prefix(5)) { game in
                                    NavigationLink(value: NavigationDestination.game(game.id)) {
                                        GameRow(game: game)
                                    }
                                }
                            }
                            .textCase(nil)
                        }
                        
                        // Pending Invitations Section (only show if there are pending invitations)
                        // Safely access family.members to avoid crashes from corrupted data
                        // Explicitly filter by familyID to ensure only current family's invitations are shown
                        let pendingMembers = safeFamilyMembers(family).filter { member in
                            member.familyID == family.id && safeInvitationStatus(for: member) == .pending
                        }
                        if !pendingMembers.isEmpty {
                            Section("Pending Invitations".localized) {
                                ForEach(pendingMembers) { member in
                                    PendingMemberRow(member: member, onRemove: {
                                        removePendingInvitation(member)
                                    })
                                }
                            }
                            .textCase(nil)
                        }
                        
                        // Family Members Section (only active, accepted members)
                        Section("Family Members".localized) {
                            ForEach(safeFamilyMembers(family).filter { $0.isActive && safeInvitationStatus(for: $0) == .accepted }) { member in
                                FamilyMemberRow(member: member)
                            }
                        }
                        .textCase(nil)
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.insetGrouped)
                    .navigationTitle(family.name ?? "Family".localized)
                    .navigationBarTitleDisplayMode(.large)
                    .task {
                        // First, try to fix any corrupted FamilyMember records
                        FamilyMemberMigrationHelper.fixInvalidInvitationStatus(in: modelContext)
                        
                        // Stop all listeners except for the user's current family
                        FirebaseFamilySyncService.shared.stopAllFamilyListenersExcept(userFamilyID: currentUser?.familyID)
                        
                        // Clean up orphaned families (families that don't exist in Firestore)
                        await FirebaseFamilySyncService.shared.cleanupOrphanedFamilies()
                        
                        // Load user's family from Firestore if they have a familyID
                        if let userID = currentUser?.id, let familyID = currentUser?.familyID {
                            if let loadedFamily = try? await FirebaseFamilySyncService.shared.loadUserFamilyFromFirestore(
                                userID: userID,
                                familyID: familyID
                            ) {
                                // Family loaded successfully, continue with setup
                                print("✅ User's family loaded from Firestore: \(loadedFamily.id)")
                            }
                        }
                        
                        // Validate user is actually a member in Firestore before showing family
                        // Only validate if family is already synced to Firestore (not in the process of being created)
                        if let firebaseFamilyID = family.firebaseFamilyID,
                           let userID = currentUser?.id,
                           !family.needsSync { // Only validate if family is already synced
                            // Check if user is a member in Firestore
                            let db = Firestore.firestore()
                            let memberDocRef = db.collection("families")
                                .document(firebaseFamilyID)
                                .collection("members")
                                .document(userID)
                            
                            do {
                                let memberDoc = try await memberDocRef.getDocument()
                                
                                if memberDoc.exists, let memberData = memberDoc.data() {
                                    let isActive = memberData["isActive"] as? Bool ?? false
                                    let invitationStatus = memberData["invitationStatus"] as? String ?? "pending"
                                    
                                    // If not an active, accepted member, clear familyID
                                    if !isActive || invitationStatus != "accepted" {
                                        print("⚠️ User is not an active, accepted member in Firestore. Clearing familyID.")
                                        print("   isActive: \(isActive), invitationStatus: \(invitationStatus)")
                                        currentUser?.familyID = nil
                                        currentUser?.needsSync = true
                                        try? modelContext.save()
                                        return // Don't continue loading family data
                                    }
                                } else {
                                    // Member doesn't exist in Firestore, but only clear if family is fully synced
                                    // (not in the process of being created)
                                    print("⚠️ User member document doesn't exist in Firestore.")
                                    print("   Family needsSync: \(family.needsSync)")
                                    print("   Family firebaseFamilyID: \(firebaseFamilyID)")
                                    print("   User familyID: \(currentUser?.familyID?.uuidString ?? "nil")")
                                    
                                    // Only clear if family is already synced (not being created)
                                    if !family.needsSync {
                                        print("   Clearing familyID because family is synced but member doesn't exist")
                                        currentUser?.familyID = nil
                                        currentUser?.needsSync = true
                                        try? modelContext.save()
                                        return // Don't continue loading family data
                                    } else {
                                        print("   Family is still syncing, keeping familyID")
                                    }
                                }
                            } catch {
                                print("⚠️ Error validating membership in Firestore: \(error)")
                                // If we can't validate (e.g., offline), allow cached data but log warning
                            }
                        } else if family.needsSync {
                            print("🔍 DEBUG - Skipping Firestore validation: family.needsSync = true (family is being created/synced)")
                        }
                        
                        // Sync from Firebase if needsSync is false (Firebase is source of truth)
                        if let firebaseFamilyID = family.firebaseFamilyID, !family.needsSync {
                            _ = try? await FirebaseFamilySyncService.shared.loadFamilyFromFirestore(familyID: firebaseFamilyID)
                        }
                        
                        // Then load family members manually to handle any remaining errors
                        await loadFamilyMembers()
                        
                        // Start listening to family member changes in real-time
                        if let firebaseFamilyID = family.firebaseFamilyID {
                            FirebaseFamilySyncService.shared.startListeningToFamily(
                                familyID: family.id,
                                firebaseFamilyID: firebaseFamilyID
                            ) {
                                // Reload family members when updates occur
                                Task {
                                    await loadFamilyMembers()
                                    // Also reload the family from Firestore to get latest data
                                    if let firebaseID = family.firebaseFamilyID {
                                        _ = try? await FirebaseFamilySyncService.shared.loadFamilyFromFirestore(familyID: firebaseID)
                                    }
                                }
                            }
                        }
                        
                        // Pre-fetch all family member userNames to populate cache
                        let safeMembers = safeFamilyMembers(family)
                        let memberIDs = safeMembers.filter { $0.isActive }.map { $0.userID }
                        if !memberIDs.isEmpty {
                            memberUserNames = await UserLookupHelper.getUserNames(for: memberIDs, in: modelContext)
                        }
                    }
                    .onDisappear {
                        // Stop listening when view disappears
                        if let family = currentFamily {
                            FirebaseFamilySyncService.shared.stopListeningToFamily(familyID: family.id)
                        }
                    }
                } else {
                    // No Family - Create or Join
                    VStack(spacing: 24) {
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(Color.Theme.primaryBlue.opacity(0.6))
                        
                        Text("No Family Yet".localized)
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Create or join a family to start playing together!".localized)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button {
                            showInviteFamily = true
                        } label: {
                            Text("Create or Join Family".localized)
                                .font(.headline)
                                .foregroundStyle(.white)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.Theme.primaryBlue)
                                .cornerRadius(12)
                        }
                        .padding(.horizontal)
                    }
                    .padding()
                    .navigationTitle("Family".localized)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                    
                            Button {
                                showFamilyInvitations = true
                            } label: {
                                ZStack {
                                    Image(systemName: "envelope.fill")
                                        .foregroundStyle(Color.Theme.primaryBlue)
                                    if pendingInvitationsCount > 0 {
                                        Text("\(pendingInvitationsCount)")
                                            .font(.caption2)
                                            .foregroundStyle(.white)
                                            .padding(4)
                                            .background(Color.red)
                                            .clipShape(Circle())
                                            .offset(x: 8, y: -8)
                                    }
                                }
                            }
                            .accessibilityLabel("Family Invitations (\(pendingInvitationsCount))".localized)
                      
                        
                        if currentFamily != nil {
                            Button {
                                showFamilySettings = true
                            } label: {
                                Image(systemName: "gearshape")
                                    .foregroundStyle(Color.Theme.primaryBlue)
                            }
                            .accessibilityLabel("Family Settings".localized)
                        }
                    }
                }
                
                ToolbarItem(placement: .topBarLeading) {
                    if currentFamily != nil {
                        Button {
                            showInviteFamily = true
                        } label: {
                            Image(systemName: "person.badge.plus")
                                .foregroundStyle(Color.Theme.primaryBlue)
                        }
                        .accessibilityLabel("Invite a Family Member".localized)
                    }
                }
            }
            .sheet(isPresented: $showFamilyInvitations) {
                FamilyInvitationsView()
                    .onDisappear {
                        // Refresh when sheet closes to update family view
                        Task {
                            // Reload family members
                            await loadFamilyMembers()
                            
                            // If user now has a familyID, load the family from Firestore
                            if let userID = currentUser?.id,
                               let familyID = currentUser?.familyID,
                               let family = families.first(where: { $0.id == familyID }),
                               let firebaseID = family.firebaseFamilyID {
                                _ = try? await FirebaseFamilySyncService.shared.loadFamilyFromFirestore(familyID: firebaseID)
                            }
                        }
                    }
            }
            .sheet(isPresented: $showFamilySettings) {
                if let family = currentFamily {
                    FamilySettingsView(family: family)
                }
            }
            .sheet(isPresented: $showInviteFamily) {
                InviteToFamilyView(family: currentFamily)
            }
        }
    
    
    @ViewBuilder
    private func familyOverview(family: Family) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Family Stats".localized)
                        .font(.headline)
                    if let name = family.name {
                        Text(name)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            
            HStack(spacing: 24) {
                StatCard(
                    title: "Members".localized,
                    value: "\(family.members.filter { $0.isActive }.count)",
                    icon: "person.3.fill"
                )
                
                StatCard(
                    title: "Trips".localized,
                    value: "\(sharedTrips.count)",
                    icon: "map.fill"
                )
                
                StatCard(
                    title: "Games".localized,
                    value: "\(activeGames.count)",
                    icon: "gamecontroller.fill"
                )
            }
        }
        .padding(.vertical, 8)
    }

}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.Theme.primaryBlue)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.Theme.cardBackground)
        .cornerRadius(12)
    }
}

struct PendingMemberRow: View {
    let member: FamilyMember
    let onRemove: (() -> Void)?
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authService: FirebaseAuthService
    @State private var userName: String = "Unknown User".localized
    @State private var inviterName: String = "Unknown User".localized
    @State private var showRemoveConfirmation = false
    
    init(member: FamilyMember, onRemove: (() -> Void)? = nil) {
        self.member = member
        self.onRemove = onRemove
    }
    
    var isCaptain: Bool {
        guard let userID = authService.currentUser?.id,
              let family = member.family else { return false }
        return family.members.contains { $0.userID == userID && $0.role == .captain && $0.isActive }
    }
    
    var body: some View {
        HStack {
            Image(systemName: "person.crop.circle")
                .font(.title2)
                .foregroundStyle(Color.orange)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(userName)
                    .font(.headline)
                
                HStack {
                    Text(member.role.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    if let invitedAt = member.invitedAt {
                        HStack(spacing: 4) {
                            Text("• Invited".localized)
                            Text(invitedAt, style: .relative)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                
                if let invitedBy = member.invitedBy {
                    Text("Invited by \(inviterName)".localized)
                        .font(.caption)
                        .foregroundStyle(Color.orange)
                }
            }
            
            Spacer()
            
            if isCaptain && onRemove != nil {
                Button(role: .destructive) {
                    showRemoveConfirmation = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.vertical, 4)
        .alert("Remove Invitation".localized, isPresented: $showRemoveConfirmation) {
            Button("Cancel".localized, role: .cancel) { }
            Button("Remove".localized, role: .destructive) {
                onRemove?()
            }
        } message: {
            Text("Are you sure you want to cancel this invitation?".localized)
        }
        .task {
            // Fetch member userName
            if let fetchedUserName = await UserLookupHelper.getUserName(for: member.userID, in: modelContext) {
                userName = fetchedUserName
            }
            
            // Fetch inviter userName
            if let invitedBy = member.invitedBy {
                if let fetchedInviterName = await UserLookupHelper.getUserName(for: invitedBy, in: modelContext) {
                    inviterName = fetchedInviterName
                }
            }
        }
    }
}

struct FamilyMemberRow: View {
    let member: FamilyMember
    @Environment(\.modelContext) private var modelContext
    @State private var userName: String
    @State private var firstName: String?
    @State private var lastName: String?
    
    init(member: FamilyMember) {
        self.member = member
        // Initialize with local cache if available, otherwise "Unknown User"
        // We'll use a temporary modelContext to check, but this won't work in init
        // So we'll start with "Unknown User" and update immediately
        _userName = State(initialValue: "Unknown User".localized)
    }
    
    var fullName: String {
        if let firstName = firstName, let lastName = lastName, !firstName.isEmpty, !lastName.isEmpty {
            return "\(firstName) \(lastName)"
        } else if let firstName = firstName, !firstName.isEmpty {
            return firstName
        } else if let lastName = lastName, !lastName.isEmpty {
            return lastName
        }
        return ""
    }
    
    var body: some View {
        HStack {
            Image(systemName: "person.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.Theme.primaryBlue)
            
            VStack(alignment: .leading, spacing: 4) {
                // Show userName as primary
                Text(userName)
                    .font(.headline)
                
                // Show first/last name if available
                if !fullName.isEmpty {
                    Text(fullName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Text(member.role.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
        .task {
            // First check local cache synchronously
            if let cachedUser = await UserLookupHelper.getUser(for: member.userID, in: modelContext) {
                userName = cachedUser.userName
                firstName = cachedUser.firstName
                lastName = cachedUser.lastName
            } else if let cachedUserName = UserLookupHelper.getUserNameSync(for: member.userID, in: modelContext) {
                userName = cachedUserName
            }
            
            // Then try async lookup (Firestore + cache)
            if let fetchedUser = await UserLookupHelper.getUser(for: member.userID, in: modelContext) {
                userName = fetchedUser.userName
                firstName = fetchedUser.firstName
                lastName = fetchedUser.lastName
            } else if let fetchedUserName = await UserLookupHelper.getUserName(for: member.userID, in: modelContext) {
                userName = fetchedUserName
            }
        }
    }
}

struct GameRow: View {
    let game: Game
    
    var body: some View {
        HStack {
            Image(systemName: game.isActive ? "gamecontroller.fill" : "gamecontroller")
                .font(.title3)
                .foregroundStyle(Color.Theme.primaryBlue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(game.name)
                    .font(.headline)
                
                Text("\(game.gameMode.displayName) • \(game.scoringType.displayName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if game.isActive {
                Text("Active".localized)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.2))
                    .foregroundStyle(.green)
                    .cornerRadius(8)
            }
        }
        .padding(.vertical, 4)
    }
}

