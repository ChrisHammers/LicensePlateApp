//
//  FamilyHubView.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import SwiftUI
import SwiftData

struct FamilyHubView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authService: FirebaseAuthService
    @Query(sort: \Family.createdAt, order: .reverse) private var families: [Family]
    @Query(sort: \Trip.createdAt, order: .reverse) private var allTrips: [Trip]
    @Query(sort: \Game.createdAt, order: .reverse) private var allGames: [Game]
    
    @State private var selectedFamily: Family?
    @State private var showFamilySettings = false
    @State private var showInviteFamily = false
    @State private var navigationPath: [NavigationDestination] = []
    
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
                        
                        // Family Members Section
                        Section("Family Members".localized) {
                            ForEach(family.members.filter { $0.isActive }) { member in
                                FamilyMemberRow(member: member)
                            }
                        }
                        .textCase(nil)
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.insetGrouped)
                    .navigationTitle(family.name ?? "Family".localized)
                    .navigationBarTitleDisplayMode(.large)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                showFamilySettings = true
                            } label: {
                                Image(systemName: "gearshape")
                                    .foregroundStyle(Color.Theme.primaryBlue)
                            }
                            .accessibilityLabel("Family Settings".localized)
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

struct FamilyMemberRow: View {
    let member: FamilyMember
    
    var body: some View {
        HStack {
            Image(systemName: "person.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.Theme.primaryBlue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("User \(member.userID.prefix(8))")
                    .font(.headline)
                
                Text(member.role.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
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

