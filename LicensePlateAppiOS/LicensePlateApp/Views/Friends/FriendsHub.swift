//
//  FriendsHub.swift
//  LicensePlateApp
//
//  Created for Friends & Family MVP
//

import SwiftUI
import SwiftData

struct FriendsHub: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authService: FirebaseAuthService
    @StateObject private var viewModel: FriendsHubViewModel
    @State private var showAddFriendSheet = false
    @State private var showCreateShareCodeSheet = false
    @State private var showJoinByCodeSheet = false
    
    init() {
        // ViewModel will be initialized with singleton repositories and authService from environment
        _viewModel = StateObject(wrappedValue: FriendsHubViewModel(
            friendshipRepository: .shared,
            inviteRepository: .shared,
            authService: FirebaseAuthService()
        ))
    }
    
    var body: some View {
      //  NavigationStack {
            ZStack {
                Color.Theme.background
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Segmented control
                    Picker("", selection: $viewModel.selectedTab) {
                        Text("Friends".localized).tag(FriendsHubViewModel.FriendsTab.friends)
                        
                        HStack(spacing: 4) {
                            Text("Requests".localized)
                            if viewModel.pendingFriendRequestsCount > 0 {
                              // This doesn't work on a Picker
                                BadgeView(count: viewModel.pendingFriendRequestsCount, size: 16)
                            }
                        }
                        .tag(FriendsHubViewModel.FriendsTab.requests)
                    }
                    .pickerStyle(.segmented)
                    .padding()
                    
                    // Content
                    if viewModel.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            if viewModel.selectedTab == .friends {
                                friendsList
                            } else {
                                requestsList
                            }
                        }
                        .listStyle(.insetGrouped)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Friends".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showAddFriendSheet = true
                        } label: {
                            Label("Search for Friend".localized, systemImage: "person.badge.plus")
                        }
                        
                        Button {
                            showCreateShareCodeSheet = true
                        } label: {
                            Label("Create Share Code".localized, systemImage: "qrcode")
                        }
                        
                        Button {
                            showJoinByCodeSheet = true
                        } label: {
                            Label("Enter Share Code".localized, systemImage: "text.magnifyingglass")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(Color.Theme.primaryBlue)
                    }
                }
            }
            .sheet(isPresented: $showAddFriendSheet) {
                AddFriendSheet()
                    .environmentObject(authService)
            }
            .sheet(isPresented: $showCreateShareCodeSheet) {
                CreateFriendShareCodeSheet()
                    .environmentObject(authService)
            }
            .sheet(isPresented: $showJoinByCodeSheet) {
                JoinFriendByCodeSheet()
                    .environmentObject(authService)
            }
            .onAppear {
                viewModel.setModelContext(modelContext)
                viewModel.setAuthService(authService) // Use the environment authService
                viewModel.loadData()
                AnalyticsService.shared.log(.friendsScreenOpened)
                AnalyticsService.shared.logScreenView(screenName: "friends")
            }
      //  }
    }
    
    private var friendsList: some View {
        Group {
            if viewModel.friends.isEmpty {
                VStack(spacing: 16) {
                    Text("No friends yet".localized)
                        .foregroundStyle(Color.Theme.softBrown)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                    
                    VStack(spacing: 12) {
                        Button {
                            showCreateShareCodeSheet = true
                        } label: {
                            HStack {
                                Image(systemName: "qrcode")
                                Text("Create Share Code".localized)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.Theme.primaryBlue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        
                        Button {
                            showJoinByCodeSheet = true
                        } label: {
                            HStack {
                                Image(systemName: "text.magnifyingglass")
                                Text("Enter Share Code".localized)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.Theme.cardBackground)
                            .foregroundColor(Color.Theme.primaryBlue)
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                }
            } else {
                ForEach(viewModel.friends) { friendship in
                    FriendRow(friendship: friendship)
                }
            }
        }
    }
    
    private var requestsList: some View {
        Group {
            Section("Incoming".localized) {
                if viewModel.incomingRequests.isEmpty && viewModel.incomingFriendInvites.isEmpty {
                    Text("No incoming requests".localized)
                        .foregroundStyle(Color.Theme.softBrown)
                } else {
                    // Show friend invites first
                    ForEach(viewModel.incomingFriendInvites) { invite in
                        FriendInviteRow(invite: invite)
                    }
                    // Then show legacy friendship requests
                    ForEach(viewModel.incomingRequests) { friendship in
                        FriendRequestRow(friendship: friendship)
                    }
                }
            }
            
            Section("Outgoing".localized) {
                if viewModel.outgoingRequests.isEmpty && viewModel.outgoingFriendInvites.isEmpty {
                    Text("No outgoing requests".localized)
                        .foregroundStyle(Color.Theme.softBrown)
                } else {
                    // Show friend invites first
                    ForEach(viewModel.outgoingFriendInvites) { invite in
                        FriendInviteRow(invite: invite, isOutgoing: true)
                    }
                    // Then show legacy friendship requests
                    ForEach(viewModel.outgoingRequests) { friendship in
                        FriendRequestRow(friendship: friendship, isOutgoing: true)
                    }
                }
            }
        }
    }
}

struct FriendRow: View {
    let friendship: Friendship
    @EnvironmentObject var authService: FirebaseAuthService
    @Environment(\.modelContext) private var modelContext
    @State private var user: AppUser?
    
    // Get the other user's ID
    private var otherUserId: String? {
        guard let currentUserId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id else {
            return nil
        }
        return friendship.otherUser(than: currentUserId)
    }
    
    var body: some View {
        HStack {
            if let user = user {
                // User Avatar
                UserImageView(user: user, size: 50)
            } else {
                // Avatar placeholder
                Circle()
                    .fill(Color.Theme.primaryBlue.opacity(0.3))
                    .frame(width: 50, height: 50)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                if let user = user {
                    Text(user.displayName)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                    
                    Text("@\(user.userName)")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                } else {
                    Text("Friend".localized)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                    
                    if let userId = otherUserId {
                        Text(userId)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .task {
            await loadUser()
        }
    }
    
    private func loadUser() async {
        guard let userId = otherUserId else { return }
        
        do {
            if let fetchedUser = try await UserRepository.shared.getUser(userId: userId) {
                await MainActor.run {
                    self.user = fetchedUser
                }
            }
        } catch {
            print("⚠️ Failed to load user \(userId): \(error.localizedDescription)")
        }
    }
}

struct FriendRequestRow: View {
    let friendship: Friendship
    var isOutgoing: Bool = false
    @EnvironmentObject var authService: FirebaseAuthService
    @Environment(\.modelContext) private var modelContext
    @State private var user: AppUser?
    
    // Get the other user's ID
    private var otherUserId: String? {
        guard let currentUserId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id else {
            return nil
        }
        return friendship.otherUser(than: currentUserId)
    }
    
    var body: some View {
        HStack {
            if let user = user {
                // User Avatar
                UserImageView(user: user, size: 50)
            } else {
                // Avatar placeholder
                Circle()
                    .fill(Color.Theme.primaryBlue.opacity(0.3))
                    .frame(width: 50, height: 50)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                if let user = user {
                    Text(user.displayName)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                    
                    Text("@\(user.userName)")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                } else {
                    Text("Friend Request".localized)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                    
                    Text(isOutgoing ? "Waiting for response".localized : "Tap to respond".localized)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .task {
            await loadUser()
        }
    }
    
    private func loadUser() async {
        guard let userId = otherUserId else { return }
        
        do {
            if let fetchedUser = try await UserRepository.shared.getUser(userId: userId) {
                await MainActor.run {
                    self.user = fetchedUser
                }
            }
        } catch {
            print("⚠️ Failed to load user \(userId): \(error.localizedDescription)")
        }
    }
}

struct FriendInviteRow: View {
    let invite: Invite
    var isOutgoing: Bool = false
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authService: FirebaseAuthService
    @State private var showInviteDetail = false
    @State private var user: AppUser?
    
    // Determine which userId to fetch
    private var targetUserId: String? {
        if isOutgoing {
            return invite.toUserId
        } else {
            return invite.fromUserId
        }
    }
    
    var body: some View {
        Button {
            if !isOutgoing {
                showInviteDetail = true
            }
        } label: {
            HStack {
                Circle()
                    .fill(Color.Theme.primaryBlue.opacity(0.3))
                    .frame(width: 50, height: 50)
                
                VStack(alignment: .leading, spacing: 4) {
                    if let user = user {
                        Text(user.displayName)
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.Theme.primaryBlue)
                        
                        Text("@\(user.userName)")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                    } else {
                        Text("Friend Request".localized)
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.Theme.primaryBlue)
                        
                        Text(isOutgoing ? "Waiting for response".localized : "Tap to respond".localized)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                    }
                }
                
                Spacer()
                
                if !isOutgoing {
                    Image(systemName: "chevron.right")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                }
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showInviteDetail) {
            FriendInviteDetail(inviteId: invite.inviteId)
                .environmentObject(authService)
        }
        .task {
            await loadUser()
        }
    }
    
    private func loadUser() async {
        guard let userId = targetUserId else { return }
        
        do {
            if let fetchedUser = try await UserRepository.shared.getUser(userId: userId) {
                await MainActor.run {
                    self.user = fetchedUser
                }
            }
        } catch {
            print("⚠️ Failed to load user \(userId): \(error.localizedDescription)")
        }
    }
}

#Preview {
    FriendsHub()
        .environmentObject(FirebaseAuthService())
        .modelContainer(for: [Friendship.self], inMemory: true)
}

