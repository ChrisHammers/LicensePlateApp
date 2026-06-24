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
    @State private var pendingRemoval: Friendship?
    @State private var showRemoveFriendConfirm = false

    init() {
        _viewModel = StateObject(wrappedValue: FriendsHubViewModel(
            friendshipRepository: .shared,
            inviteRepository: .shared,
            authService: FirebaseAuthService()
        ))
    }

    var body: some View {
        AppBackgroundView {
            VStack(spacing: 0) {
                friendsHubTabBar
                    .padding()

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
                .accessibilityLabel("Add friend options".localized)
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
            viewModel.setAuthService(authService)
            viewModel.loadData()
            viewModel.logFriendsHubAppeared()
        }
        .confirmationDialog(
            "Remove this friend? You can send a new request later.".localized,
            isPresented: $showRemoveFriendConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove friend".localized, role: .destructive) {
                if let f = pendingRemoval {
                    viewModel.removeFriend(f)
                }
                pendingRemoval = nil
            }
            Button("Cancel".localized, role: .cancel) {
                pendingRemoval = nil
            }
        }
        .alert("Error".localized, isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK".localized, role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            if let msg = viewModel.errorMessage {
                Text(msg)
            }
        }
    }

    private var friendsHubTabBar: some View {
        HStack(spacing: 0) {
            tabPill(
                title: "Friends".localized,
                tab: .friends,
                accessibilityId: "friends_tab_friends"
            )
            tabPill(
                title: "Requests".localized,
                tab: .requests,
                badge: viewModel.pendingFriendRequestsCount,
                accessibilityId: "friends_tab_requests"
            )
        }
        .padding(4)
        .background(Color.Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Friends hub section".localized)
    }

    private func tabPill(
        title: String,
        tab: FriendsHubViewModel.FriendsTab,
        badge: Int = 0,
        accessibilityId: String
    ) -> some View {
        Button {
            viewModel.selectedTab = tab
            FeedbackService.shared.selectionChange()
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(viewModel.selectedTab == tab ? .semibold : .regular)
                if badge > 0, tab == .requests {
                    BadgeView(count: badge, size: 16)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(viewModel.selectedTab == tab ? Color.Theme.primaryBlue.opacity(0.2) : Color.clear)
            )
            .foregroundStyle(viewModel.selectedTab == tab ? Color.Theme.primaryBlue : Color.Theme.softBrown)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityId)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(
            tab == .requests && badge > 0
                ? "Pending incoming friend requests".localized
                : ""
        )
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
                        .accessibilityLabel("Create Share Code".localized)

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
                        .accessibilityLabel("Enter Share Code".localized)
                    }
                    .padding(.horizontal)
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(viewModel.friends) { friendship in
                    FriendRow(friendship: friendship) {
                        pendingRemoval = friendship
                        showRemoveFriendConfirm = true
                    }
                }
                .listRowBackground(Color.Theme.cardBackground)
            }
        }
    }

    private var requestsList: some View {
        Group {
            Section("Incoming".localized) {
                if viewModel.incomingFriendInvites.isEmpty {
                    Text("No incoming requests".localized)
                        .foregroundStyle(Color.Theme.softBrown)
                } else {
                    ForEach(viewModel.incomingFriendInvites) { invite in
                        FriendInviteRow(invite: invite)
                    }
                }
            }
            .listRowBackground(Color.Theme.cardBackground)

            Section("Outgoing".localized) {
                if viewModel.outgoingFriendInvites.isEmpty {
                    Text("No outgoing requests".localized)
                        .foregroundStyle(Color.Theme.softBrown)
                } else {
                    ForEach(viewModel.outgoingFriendInvites) { invite in
                        FriendInviteRow(invite: invite, isOutgoing: true)
                    }
                }
            }
            .listRowBackground(Color.Theme.cardBackground)
        }
    }
}

struct FriendRow: View {
    let friendship: Friendship
    var onRemoveRequested: () -> Void
    @EnvironmentObject var authService: FirebaseAuthService
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var publicLifetimeStatsRepository = PublicLifetimeStatsRepository.shared
    @State private var user: AppUser?

    private var otherUserId: String? {
        guard let currentUserId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id else {
            return nil
        }
        return friendship.otherUser(than: currentUserId)
    }

    var body: some View {
        if let user {
            NavigationLink {
                StandardProfileView(user: user)
            } label: {
                rowContent
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabelText)
            .accessibilityHint("Opens profile".localized)
            .task {
                if let oid = otherUserId {
                    publicLifetimeStatsRepository.ensureObservingFriend(userId: oid)
                }
                await loadUser()
            }
        } else {
            rowContent
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityLabelText)
                .task {
                    if let oid = otherUserId {
                        publicLifetimeStatsRepository.ensureObservingFriend(userId: oid)
                    }
                    await loadUser()
                }
        }
    }

    private var rowContent: some View {
        HStack {
            if let user = user {
                UserImageView(user: user, size: 50)
            } else {
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

                    if let oid = otherUserId, let stats = publicLifetimeStatsRepository.snapshot(forUserId: oid) {
                        Text("friends.public_lifetime_stats.trips_line".localized(stats.totalCompletedTrips))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown.opacity(0.85))
                            .accessibilityLabel(
                                "friends.public_lifetime_stats.trips_line.a11y".localized(stats.totalCompletedTrips)
                            )
                    }
                } else {
                    Text("Friend".localized)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.Theme.primaryBlue)

                    Text("Loading profile…".localized)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                }
            }

            Spacer()
        }
        .padding(.vertical, 8)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                onRemoveRequested()
            } label: {
                Label("Remove friend".localized, systemImage: "person.crop.circle.badge.minus")
            }
            .accessibilityLabel("Remove friend".localized)
            .accessibilityHint("Removes this person from your friends list".localized)
        }
        .contextMenu {
            Button(role: .destructive) {
                onRemoveRequested()
            } label: {
                Label("Remove friend".localized, systemImage: "person.crop.circle.badge.minus")
            }
        }
    }

    private var accessibilityLabelText: String {
        if let user = user {
            if let oid = otherUserId, let stats = publicLifetimeStatsRepository.snapshot(forUserId: oid) {
                return "\(user.displayName), @\(user.userName), \("friends.public_lifetime_stats.trips_line".localized(stats.totalCompletedTrips))"
            }
            return "\(user.displayName), @\(user.userName)"
        }
        return "Friend".localized
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
            #if DEBUG
            print("⚠️ Failed to load user \(userId): \(error.localizedDescription)")
            #endif
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
        .accessibilityLabel(isOutgoing ? "Outgoing friend request".localized : "Incoming friend request".localized)
        .accessibilityHint(isOutgoing ? "" : "Opens request details".localized)
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
            #if DEBUG
            print("⚠️ Failed to load user \(userId): \(error.localizedDescription)")
            #endif
        }
    }
}

#Preview {
    FriendsHub()
        .environmentObject(FirebaseAuthService())
        .modelContainer(for: [Friendship.self], inMemory: true)
}
