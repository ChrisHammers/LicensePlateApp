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
        guard let userID = currentUser?.id,
              let familyID = currentUser?.familyID else {
            return nil
        }
        return families.first { $0.id == familyID }
    }
    
    var pendingInvitationsCount: Int {
        guard let userID = currentUser?.id else { return 0 }
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
                                    PendingMemberRow(member: member)
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
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            HStack {
                                if pendingInvitationsCount > 0 {
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
                                }
                                
                                Button {
                                    showFamilySettings = true
                                } label: {
                                    Image(systemName: "gearshape")
                                        .foregroundStyle(Color.Theme.primaryBlue)
                                }
                                .accessibilityLabel("Family Settings".localized)
                            }
                        }
                        
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                showInviteFamily = true
                            } label: {
                                Image(systemName: "person.badge.plus")
                                    .foregroundStyle(Color.Theme.primaryBlue)
                            }
                            .accessibilityLabel("Invite a Family Member".localized)
                        }
                    }
                    .sheet(isPresented: $showFamilySettings) {
                        FamilySettingsView(family: family)
                    }
                    .sheet(isPresented: $showInviteFamily) {
                        InviteToFamilyView(family: family)
                    }
                    .sheet(isPresented: $showFamilyInvitations) {
                        FamilyInvitationsView()
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
                    .sheet(isPresented: $showInviteFamily) {
                        InviteToFamilyView(family: nil)
                    }
                }
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
    @Environment(\.modelContext) private var modelContext
    @State private var userName: String = "Unknown User".localized
    @State private var inviterName: String = "Unknown User".localized
    
    var body: some View {
        HStack {
            Image(systemName: "person.circle.dashed")
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
        }
        .padding(.vertical, 4)
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
    
    init(member: FamilyMember) {
        self.member = member
        // Initialize with local cache if available, otherwise "Unknown User"
        // We'll use a temporary modelContext to check, but this won't work in init
        // So we'll start with "Unknown User" and update immediately
        _userName = State(initialValue: "Unknown User".localized)
    }
    
    var body: some View {
        HStack {
            Image(systemName: "person.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.Theme.primaryBlue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(userName)
                    .font(.headline)
                
                Text(member.role.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
        .task {
            // First check local cache synchronously
            if let cachedUserName = UserLookupHelper.getUserNameSync(for: member.userID, in: modelContext) {
                userName = cachedUserName
            }
            
            // Then try async lookup (Firestore + cache)
            if let fetchedUserName = await UserLookupHelper.getUserName(for: member.userID, in: modelContext) {
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

