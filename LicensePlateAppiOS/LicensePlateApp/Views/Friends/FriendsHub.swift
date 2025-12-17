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
        // ViewModel will be initialized with authService from environment
        _viewModel = StateObject(wrappedValue: FriendsHubViewModel(
            friendshipRepository: FriendshipRepository(),
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
                        Text("Requests".localized).tag(FriendsHubViewModel.FriendsTab.requests)
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
                viewModel.loadData()
                AnalyticsService.shared.log(.friendsScreenOpened)
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
                if viewModel.incomingRequests.isEmpty {
                    Text("No incoming requests".localized)
                        .foregroundStyle(Color.Theme.softBrown)
                } else {
                    ForEach(viewModel.incomingRequests) { friendship in
                        FriendRequestRow(friendship: friendship)
                    }
                }
            }
            
            Section("Outgoing".localized) {
                if viewModel.outgoingRequests.isEmpty {
                    Text("No outgoing requests".localized)
                        .foregroundStyle(Color.Theme.softBrown)
                } else {
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
    
    var body: some View {
        HStack {
            // Avatar placeholder
            Circle()
                .fill(Color.Theme.primaryBlue.opacity(0.3))
                .frame(width: 50, height: 50)
            
            VStack(alignment: .leading) {
                Text("Friend") // TODO: Get actual user name
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                
                Text(friendship.otherUser(than: authService.currentUser?.id ?? "") ?? "")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

struct FriendRequestRow: View {
    let friendship: Friendship
    var isOutgoing: Bool = false
    
    var body: some View {
        HStack {
            Circle()
                .fill(Color.Theme.primaryBlue.opacity(0.3))
                .frame(width: 50, height: 50)
            
            VStack(alignment: .leading) {
                Text("Friend Request")
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                
                Text(isOutgoing ? "Waiting for response" : "Tap to respond")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    FriendsHub()
        .environmentObject(FirebaseAuthService())
        .modelContainer(for: [Friendship.self], inMemory: true)
}

