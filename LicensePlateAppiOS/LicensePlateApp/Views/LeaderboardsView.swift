//
//  LeaderboardsView.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import SwiftUI
import SwiftData

struct LeaderboardsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authService: FirebaseAuthService
    @Query(sort: \AppUser.userName) private var allUsers: [AppUser]
    @Query(sort: \Family.createdAt) private var allFamilies: [Family]
    
    @State private var selectedTab: LeaderboardTab = .global
    @State private var timeFilter: TimeFilter = .allTime
    
    enum LeaderboardTab: String, CaseIterable {
        case global = "Global"
        case family = "Family"
        case friends = "Friends"
        
        var displayName: String {
            switch self {
            case .global: return "Global".localized
            case .family: return "Family".localized
            case .friends: return "Friends".localized
            }
        }
    }
    
    enum TimeFilter: String, CaseIterable {
        case allTime = "All Time"
        case thisMonth = "This Month"
        case thisYear = "This Year"
        
        var displayName: String {
            switch self {
            case .allTime: return "All Time".localized
            case .thisMonth: return "This Month".localized
            case .thisYear: return "This Year".localized
            }
        }
    }
    
    var currentUser: AppUser? {
        authService.currentUser
    }
    
    var currentFamily: Family? {
        guard let familyID = currentUser?.familyID else { return nil }
        return allFamilies.first { $0.id == familyID }
    }
    
    var friends: [AppUser] {
        guard let userID = currentUser?.id else { return [] }
        return allUsers.filter { currentUser?.friendIDs.contains($0.id) == true }
    }
    
    var familyMembers: [AppUser] {
        guard let family = currentFamily else { return [] }
        return allUsers.filter { user in
            family.members.contains { $0.userID == user.id && $0.isActive }
        }
    }
    
    var displayedUsers: [AppUser] {
        switch selectedTab {
        case .global:
            return allUsers
        case .family:
            return familyMembers
        case .friends:
            return friends
        }
    }
    
    var sortedUsers: [AppUser] {
        // In a real implementation, this would calculate scores based on trips
        // For now, just return users sorted by username
        displayedUsers.sorted { $0.userName < $1.userName }
    }
    
    var body: some View {
        NavigationStack {
            AppBackgroundView {
                VStack(spacing: 0) {
                    // Tab Picker
                    Picker("Leaderboard Type".localized, selection: $selectedTab) {
                        ForEach(LeaderboardTab.allCases, id: \.self) { tab in
                            Text(tab.displayName).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding()
                    
                    // Time Filter
                    Picker("Time Filter".localized, selection: $timeFilter) {
                        ForEach(TimeFilter.allCases, id: \.self) { filter in
                            Text(filter.displayName).tag(filter)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal)
                    
                    // Leaderboard List
                    List {
                        ForEach(Array(sortedUsers.enumerated()), id: \.element.id) { index, user in
                            LeaderboardUserRow(
                                user: user,
                                rank: index + 1,
                                isCurrentUser: user.id == currentUser?.id
                            )
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.insetGrouped)
                }
                .navigationTitle("Leaderboards".localized)
                .navigationBarTitleDisplayMode(.large)
            }
        }
    }
}

struct LeaderboardUserRow: View {
    let user: AppUser
    let rank: Int
    let isCurrentUser: Bool
    
    // Placeholder score - in real implementation, calculate from trips
    var score: Int {
        // Placeholder: random score for demo
        rank * 10
    }
    
    var body: some View {
        HStack {
            // Rank
            Text("\(rank)")
                .font(.title2)
                .fontWeight(.bold)
                .frame(width: 40)
                .foregroundStyle(rank <= 3 ? Color.Theme.accentYellow : .secondary)
            
            // User Avatar
            UserImageView(user: user, size: 40)
            
            // User Info
            VStack(alignment: .leading, spacing: 4) {
                Text(user.displayName)
                    .font(.headline)
                
                Text("@\(user.userName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Stats
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(score)")
                    .font(.title3)
                    .fontWeight(.bold)
                
                if isCurrentUser {
                    Text("You".localized)
                        .font(.caption)
                        .foregroundStyle(Color.Theme.primaryBlue)
                }
            }
        }
        .padding(.vertical, 4)
        .background(isCurrentUser ? Color.Theme.primaryBlue.opacity(0.1) : Color.clear)
        .cornerRadius(8)
    }
}

