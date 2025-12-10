//
//  GameLobbyView.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import SwiftUI
import SwiftData

struct GameLobbyView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authService: FirebaseAuthService
    @Bindable var game: Game
    
    @State private var showInviteTeam = false
    @State private var selectedTeam: GameTeam?
    
    var currentUser: AppUser? {
        authService.currentUser
    }
    
    var isCreator: Bool {
        game.createdBy == currentUser?.id
    }
    
    var userTeam: GameTeam? {
        guard let userID = currentUser?.id else { return nil }
        return game.teams.first { $0.isMember(userID: userID) }
    }
    
    var isPilot: Bool {
        guard let userID = currentUser?.id,
              let team = userTeam else { return false }
        return team.isPilot(userID: userID)
    }
    
    var body: some View {
        NavigationStack {
            AppBackgroundView {
                List {
                    // Game Info Section
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(game.name)
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            HStack {
                                Label(game.gameMode.displayName, systemImage: "gamecontroller.fill")
                                Spacer()
                                Label(game.scoringType.displayName, systemImage: "chart.bar.fill")
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            
                            if let maxSize = game.maxTeamSize {
                                Text("Team Size: \(game.minTeamSize)-\(maxSize) players".localized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Team Size: \(game.minTeamSize)+ players".localized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .textCase(nil)
                    
                    // Teams Section
                    Section("Teams".localized) {
                        ForEach(game.teams) { team in
                            TeamRow(team: team, isUserTeam: team.id == userTeam?.id, isPilot: isPilot && team.id == userTeam?.id) {
                                selectedTeam = team
                                showInviteTeam = true
                            }
                        }
                        
                        if isCreator && !game.hasEnded {
                            Button {
                                createNewTeam()
                            } label: {
                                Label("Add Team".localized, systemImage: "plus.circle")
                            }
                        }
                    }
                    .textCase(nil)
                    
                    // Start Game Button
                    if isCreator && !game.isActive && !game.hasEnded {
                        Section {
                            Button {
                                startGame()
                            } label: {
                                Text("Start Game".localized)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.Theme.primaryBlue)
                                    .foregroundStyle(.white)
                                    .cornerRadius(12)
                            }
                            .disabled(game.teams.isEmpty || game.teams.contains { team in
                                team.allMemberIDs.count < game.minTeamSize
                            })
                        }
                        .textCase(nil)
                    }
                    
                    // Leave Game
                    if userTeam != nil && !game.isActive {
                        Section {
                            Button(role: .destructive) {
                                leaveGame()
                            } label: {
                                Text("Leave Game".localized)
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
                .navigationTitle("Game Lobby".localized)
                .navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $showInviteTeam) {
                    if let team = selectedTeam {
                        InviteToTeamView(team: team, game: game)
                    }
                }
            }
        }
    }
    
    private func createNewTeam() {
        guard let userID = currentUser?.id else { return }
        
        let newTeam = GameTeam(
            gameID: game.id,
            pilotID: userID,
            memberIDs: []
        )
        
        game.teams.append(newTeam)
        modelContext.insert(newTeam)
    }
    
    private func startGame() {
        game.startedAt = .now
    }
    
    private func leaveGame() {
        guard let userID = currentUser?.id,
              let team = userTeam else { return }
        
        if team.isPilot(userID: userID) && team.memberIDs.count > 0 {
            // Transfer pilot role to first member
            team.changePilot(to: team.memberIDs[0])
        }
        
        team.removeMember(userID)
        
        if team.allMemberIDs.isEmpty {
            // Remove empty team
            game.teams.removeAll { $0.id == team.id }
        }
    }
}

struct TeamRow: View {
    let team: GameTeam
    let isUserTeam: Bool
    let isPilot: Bool
    let onInvite: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let name = team.name {
                    Text(name)
                        .font(.headline)
                } else {
                    Text("Team".localized)
                        .font(.headline)
                }
                
                Spacer()
                
                if isUserTeam {
                    Text("Your Team".localized)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.Theme.primaryBlue.opacity(0.2))
                        .foregroundStyle(Color.Theme.primaryBlue)
                        .cornerRadius(8)
                }
            }
            
            HStack {
                Label("Pilot: User \(team.pilotID.prefix(8))".localized, systemImage: "person.fill.checkmark")
                Spacer()
                Text("\(team.allMemberIDs.count) members".localized)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            
            if isPilot {
                Button {
                    onInvite()
                } label: {
                    Label("Invite Players".localized, systemImage: "person.badge.plus")
                        .font(.subheadline)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct InviteToTeamView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var team: GameTeam
    @Bindable var game: Game
    
    @State private var searchText: String = ""
    
    var body: some View {
        NavigationStack {
            AppBackgroundView {
                Form {
                    Section {
                        TextField("Search by username or email".localized, text: $searchText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        
                        if !searchText.isEmpty {
                            Button {
                                inviteUser()
                            } label: {
                                Text("Search and Invite".localized)
                            }
                        }
                    }
                    .textCase(nil)
                    
                    if let maxSize = game.maxTeamSize, team.allMemberIDs.count >= maxSize {
                        Section {
                            Text("Team is at maximum size (\(maxSize) players)".localized)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        .textCase(nil)
                    }
                }
                .scrollContentBackground(.hidden)
                .navigationTitle("Invite to Team".localized)
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
            }
        }
    }
    
    private func inviteUser() {
        // In a real implementation, this would search for users and add them to the team
        dismiss()
    }
}

