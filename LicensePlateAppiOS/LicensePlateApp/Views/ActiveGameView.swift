//
//  ActiveGameView.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import SwiftUI
import SwiftData

struct ActiveGameView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authService: FirebaseAuthService
    @Bindable var game: Game
    
    @State private var selectedTeam: GameTeam?
    @State private var teamMemberUserNames: [String: String] = [:] // [userID: userName]
    @State private var pilotUserNames: [String: String] = [:] // [teamID: userName]
    
    var currentUser: AppUser? {
        authService.currentUser
    }
    
    var userTeam: GameTeam? {
        guard let userID = currentUser?.id else { return nil }
        return game.teams.first { $0.isMember(userID: userID) }
    }
    
    var sortedTeams: [GameTeam] {
        game.teams.sorted { $0.score > $1.score }
    }
    
    var body: some View {
        NavigationStack {
            AppBackgroundView {
                List {
                    // Game Status
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(game.name)
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            if let startedAt = game.startedAt {
                                Text("Started \(startedAt)".localized)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .textCase(nil)
                    
                    // Leaderboard
                    Section("Leaderboard".localized) {
                        ForEach(Array(sortedTeams.enumerated()), id: \.element.id) { index, team in
                            LeaderboardRow(
                                team: team,
                                rank: index + 1,
                                isUserTeam: team.id == userTeam?.id
                            )
                        }
                    }
                    .textCase(nil)
                    
                    // Team Activity
                    if let userTeam = userTeam {
                        Section("Your Team Activity".localized) {
                            ForEach(userTeam.allMemberIDs, id: \.self) { memberID in
                                HStack {
                                    Image(systemName: "person.circle.fill")
                                        .foregroundStyle(Color.Theme.primaryBlue)
                                    
                                    Text(teamMemberUserNames[memberID] ?? "Unknown User".localized)
                                    
                                    Spacer()
                                    
                                    if memberID == userTeam.pilotID {
                                        Text("Pilot".localized)
                                            .font(.caption)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.Theme.accentYellow.opacity(0.3))
                                            .cornerRadius(8)
                                    }
                                }
                            }
                        }
                        .textCase(nil)
                        .task {
                            // Batch lookup team member userNames
                            teamMemberUserNames = await UserLookupHelper.getUserNames(for: userTeam.allMemberIDs, in: modelContext)
                        }
                    }
                    
                    // End Game (for creator or pilot)
                    if (game.createdBy == currentUser?.id || userTeam?.isPilot(userID: currentUser?.id ?? "") == true) && !game.hasEnded {
                        Section {
                            Button(role: .destructive) {
                                endGame()
                            } label: {
                                Text("End Game".localized)
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
                .navigationTitle("Active Game".localized)
                .navigationBarTitleDisplayMode(.inline)
                .task {
                    // Batch lookup pilot userNames for all teams
                    let pilotIDs = game.teams.map { $0.pilotID }
                    let pilotNames = await UserLookupHelper.getUserNames(for: pilotIDs, in: modelContext)
                    // Map to team IDs for easy lookup
                    for (index, team) in game.teams.enumerated() {
                        if index < pilotIDs.count {
                            pilotUserNames[team.id.uuidString] = pilotNames[pilotIDs[index]]
                        }
                    }
                }
            }
        }
    }
    
    private func endGame() {
        game.endedAt = .now
        
        // Calculate final scores based on scoring type
        for team in game.teams {
            // In a real implementation, calculate score based on trips and scoring type
            // For now, just set a placeholder
            team.score = team.tripIDs.count * 10
        }
    }
}

struct LeaderboardRow: View {
    let team: GameTeam
    let rank: Int
    let isUserTeam: Bool
    @Environment(\.modelContext) private var modelContext
    @State private var pilotUserName: String = "Unknown User".localized
    
    var body: some View {
        HStack {
            // Rank
            Text("\(rank)")
                .font(.title2)
                .fontWeight(.bold)
                .frame(width: 40)
                .foregroundStyle(rank <= 3 ? Color.Theme.accentYellow : .secondary)
            
            // Team Info
            VStack(alignment: .leading, spacing: 4) {
                if let name = team.name {
                    Text(name)
                        .font(.headline)
                } else {
                    Text("Team \(rank)".localized)
                        .font(.headline)
                }
                
                Text("Pilot: \(pilotUserName)".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .task {
            if let userName = await UserLookupHelper.getUserName(for: team.pilotID, in: modelContext) {
                pilotUserName = userName
            }
        }
            
            // Score
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(team.score)")
                    .font(.title3)
                    .fontWeight(.bold)
                
                if isUserTeam {
                    Text("Your Team".localized)
                        .font(.caption)
                        .foregroundStyle(Color.Theme.primaryBlue)
                }
            }
        
        .padding(.vertical, 4)
        .background(isUserTeam ? Color.Theme.primaryBlue.opacity(0.1) : Color.clear)
        .cornerRadius(8)
    }
}

