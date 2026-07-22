//
//  FamilyDashboard.swift
//  LicensePlateApp
//
//  Created for Friends & Family MVP
//

import SwiftUI
import SwiftData

struct FamilyDashboard: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authService: FirebaseAuthService
    @StateObject private var viewModel: FamilyDashboardViewModel
    @State private var showSettings = false
    @State private var showCreateFamilySheet = false
    @State private var showJoinFamilySheet = false
    @State private var showAddMemberSheet = false
    @State private var showCreateShareCodeSheet = false
    @State private var showFamilyInvitesView = false
    @State private var showPendingApprovalsView = false
    
    init() {
        // Create a temporary authService for initialization - will be replaced in onAppear
        let tempAuthService = FirebaseAuthService()
        _viewModel = StateObject(wrappedValue: FamilyDashboardViewModel(
            familyRepository: .shared,
            userRepository: UserRepository.shared,
            authService: tempAuthService
        ))
    }
    
    var body: some View {
     //   NavigationStack {
            AppBackgroundView {
                if viewModel.isLoading && viewModel.family == nil {
                    ProgressView()
                } else if let family = viewModel.family {
                    List {
                        // Header
                        Section {
                            HStack(spacing: 16) {
                                FamilyInitialAvatarView(familyName: family.name, size: 56)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(family.name)
                                        .font(.system(.title, design: .rounded))
                                        .fontWeight(.bold)
                                        .foregroundStyle(Color.Theme.primaryBlue)
                                    
                                    Text("Your family".localized)
                                        .font(.system(.subheadline, design: .rounded))
                                        .foregroundStyle(Color.Theme.softBrown)
                                }
                            }
                            .padding(.vertical, 8)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(family.name), \("Your family".localized)")
                        }
                        .listRowBackground(Color.Theme.cardBackground)
                        
                        // Members
                        Section("Members".localized) {
                            ForEach(viewModel.members) { member in
                                FamilyMemberRow(member: member)
                            }
                            
                            // Invite buttons for creators/captains
                            if viewModel.canManageFamily {
                                Button {
                                    showAddMemberSheet = true
                                } label: {
                                    HStack {
                                        Image(systemName: "person.badge.plus")
                                            .accessibleDecorative()
                                        Text("Invite a Family Member".localized)
                                    }
                                    .font(.system(.body, design: .rounded))
                                    .foregroundStyle(Color.Theme.primaryBlue)
                                }
                                .disabled(!authService.isOnline)
                                .accessibleButton(
                                    label: "Invite a Family Member".localized,
                                    hint: "family.a11y.opens_invite_member".localized
                                )
                                
                                Button {
                                    showCreateShareCodeSheet = true
                                } label: {
                                    HStack {
                                        Image(systemName: "qrcode")
                                            .accessibleDecorative()
                                        Text(viewModel.shareCodeButtonText)
                                    }
                                    .font(.system(.body, design: .rounded))
                                    .foregroundStyle(Color.Theme.primaryBlue)
                                }
                                .disabled(!authService.isOnline)
                                .accessibleButton(
                                    label: viewModel.shareCodeButtonText,
                                    hint: "family.a11y.opens_share_code".localized
                                )
                            }
                        }
                        .listRowBackground(Color.Theme.cardBackground)
                        
                        // Pending Invites Section
                        if viewModel.pendingFamilyInvitesCount > 0 {
                            Section {
                                Button {
                                    showFamilyInvitesView = true
                                } label: {
                                    HStack {
                                        Image(systemName: "envelope.fill")
                                            .foregroundStyle(Color.Theme.primaryBlue)
                                            .accessibleDecorative()
                                        Text("Pending Invites".localized)
                                            .font(.system(.body, design: .rounded))
                                            .foregroundStyle(Color.Theme.primaryBlue)
                                        Spacer()
                                        BadgeView(count: viewModel.pendingFamilyInvitesCount)
                                            .accessibilityHidden(true)
                                    }
                                }
                                .accessibleButton(
                                    label: "family.a11y.pending_invites".localized(viewModel.pendingFamilyInvitesCount),
                                    hint: "family.a11y.opens_pending_invites".localized
                                )
                            }
                            .listRowBackground(Color.Theme.cardBackground)
                        }
                        
                        // Pending Member Requests (for creators/captains)
                        if viewModel.canManageFamily && viewModel.pendingMemberRequestsCount > 0 {
                            Section("Pending Approvals".localized) {
                                ForEach(viewModel.pendingRequests) { request in
                                    PendingRequestRow(request: request)
                                }
                                
                                // Show badge count in section header if needed
                                if viewModel.pendingMemberRequestsCount > 0 {
                                    Text("\(viewModel.pendingMemberRequestsCount) request\(viewModel.pendingMemberRequestsCount == 1 ? "" : "s") pending")
                                        .font(.system(.caption, design: .rounded))
                                        .foregroundStyle(Color.Theme.softBrown)
                                }
                            }
                            .listRowBackground(Color.Theme.cardBackground)
                        } else if !viewModel.pendingRequests.isEmpty {
                            Section("Pending".localized) {
                                ForEach(viewModel.pendingRequests) { request in
                                    PendingRequestRow(request: request)
                                }
                            }
                            .listRowBackground(Color.Theme.cardBackground)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                } else {
                    // No active family - show create/join options
                    VStack(spacing: 24) {
                        Spacer()
                        
                        VStack(spacing: 12) {
                            Image(systemName: "house.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(Color.Theme.primaryBlue.opacity(0.6))
                                .accessibleDecorative()
                            
                            Text("No active family".localized)
                                .font(.system(.title2, design: .rounded))
                                .fontWeight(.bold)
                                .foregroundStyle(Color.Theme.primaryBlue)
                            
                            Text("Create a new family or join an existing one".localized)
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(Color.Theme.softBrown)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("family.a11y.empty_state".localized)
                        
                        VStack(spacing: 16) {
                            Button {
                                showCreateFamilySheet = true
                            } label: {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                        .accessibleDecorative()
                                    Text("Create New Family".localized)
                                }
                                .font(.system(.body, design: .rounded))
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.Theme.primaryBlue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                            .disabled(!authService.isOnline)
                            .accessibleButton(label: "family.a11y.create_family".localized)
                            
                            Button {
                                showJoinFamilySheet = true
                            } label: {
                                HStack {
                                    Image(systemName: "person.2.badge.plus")
                                        .accessibleDecorative()
                                    Text("Join Family".localized)
                                }
                                .font(.system(.body, design: .rounded))
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.Theme.cardBackground)
                                .foregroundColor(Color.Theme.primaryBlue)
                                .cornerRadius(12)
                            }
                            .disabled(!authService.isOnline)
                            .accessibleButton(label: "family.a11y.join_family".localized)
                        }
                        .padding(.horizontal, 32)
                        
                        if !authService.isOnline {
                            Text("Requires network connection".localized)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(Color.Theme.softBrown)
                                .padding(.top, 8)
                        }
                        
                        Spacer()
                    }
                    .sheet(isPresented: $showCreateFamilySheet) {
                        CreateFamilySheet()
                            .environmentObject(authService)
                            .onDisappear {
                                // Reload data after creating family
                                viewModel.loadData()
                            }
                    }
                    .sheet(isPresented: $showJoinFamilySheet) {
                        JoinFamilySheet()
                            .environmentObject(authService)
                            .onDisappear {
                                // Reload data after joining family
                                viewModel.loadData()
                            }
                    }
                }
            }
            .navigationTitle("Family".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if viewModel.pendingFamilyInvitesCount > 0 {
                        Button {
                            showFamilyInvitesView = true
                        } label: {
                            Image(systemName: "envelope.fill")
                                .foregroundStyle(Color.Theme.primaryBlue)
                                .badge(viewModel.pendingFamilyInvitesCount)
                        }
                        .accessibleButton(
                            label: "family.a11y.pending_invites".localized(viewModel.pendingFamilyInvitesCount),
                            hint: "family.a11y.opens_pending_invites".localized
                        )
                    }
                }
                
                if viewModel.canManageFamily {
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 16) {
                            Button {
                                showSettings = true
                            } label: {
                                Image(systemName: "gearshape")
                                    .foregroundStyle(Color.Theme.primaryBlue)
                            }
                            .accessibleButton(
                                label: "Family Settings".localized,
                                hint: "family.a11y.opens_settings".localized
                            )
                            if viewModel.pendingMemberRequestsCount > 0 {
                                Button {
                                    showPendingApprovalsView = true
                                } label: {
                                    Image(systemName: "person.badge.clock")
                                        .foregroundStyle(Color.Theme.primaryBlue)
                                    
                                }
                                .badge(viewModel.pendingMemberRequestsCount)
                                .accessibleButton(
                                    label: "family.a11y.pending_approvals".localized(viewModel.pendingMemberRequestsCount),
                                    hint: "family.a11y.opens_pending_approvals".localized
                                )
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                if let family = viewModel.family {
                    FamilySettings(familyId: family.familyId)
                        .environmentObject(authService)
                }
            }
            .sheet(isPresented: $showAddMemberSheet) {
                if let family = viewModel.family {
                    AddFamilyMemberSheet(familyId: family.familyId)
                        .environmentObject(authService)
                        .onDisappear {
                            // Reload data after inviting member
                            viewModel.loadData()
                        }
                }
            }
            .sheet(isPresented: $showCreateShareCodeSheet) {
                if let family = viewModel.family {
                    CreateFamilyShareCodeSheet(
                        familyId: family.familyId,
                        existingShareCode: viewModel.activeShareCode
                    )
                    .environmentObject(authService)
                    .onDisappear {
                        // Reload active share code after sheet closes (in case a new one was created or refreshed)
                        if let familyId = viewModel.family?.familyId {
                            Task {
                                await viewModel.loadActiveShareCode(familyId: familyId)
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showFamilyInvitesView) {
                FamilyInvitesView()
                    .environmentObject(authService)
                    .onDisappear {
                        // Reload data after responding to invites
                        viewModel.loadData()
                    }
            }
            .sheet(isPresented: $showPendingApprovalsView) {
                if let family = viewModel.family {
                    FamilyPendingApprovals(familyId: family.familyId)
                        .environmentObject(authService)
                        .onDisappear {
                            // Reload data after responding to approvals
                            viewModel.loadData()
                        }
                }
            }
            .onAppear {
                // Update ViewModel with the correct authService from environment
                viewModel.setAuthService(authService)
                viewModel.setModelContext(modelContext)
                viewModel.onAppear()
                DeferredProfileSetupStore.shared.markTouched(.family, source: "settings")
            }
            .onChange(of: viewModel.members.map(\.userId).sorted().joined(separator: ",")) { _, _ in
                PublicLifetimeStatsRepository.shared.updateFamilyPinnedUserIds(
                    Set(viewModel.members.map(\.userId))
                )
            }
       // }
    }
}

struct FamilyMemberRow: View {
    let member: FamilyMember
    @EnvironmentObject private var authService: FirebaseAuthService
    @ObservedObject private var publicLifetimeStatsRepository = PublicLifetimeStatsRepository.shared

    private var memberSubtitle: String {
        let role = member.roleEnum.displayName
        if let stats = publicLifetimeStatsRepository.snapshot(forUserId: member.userId) {
            return "\(role) · \("family.member.public_stats_line".localized(stats.totalCompletedTrips))"
        }
        return role
    }

    private var currentUserId: String? {
        authService.currentUser?.firebaseUID ?? authService.currentUser?.id
    }

    var body: some View {
        if let user = member.user {
            UserDetailNavigationLink(
                user: user,
                isSelfProfile: UserDetailNavigation.isSelfProfile(
                    user: user,
                    currentUserId: currentUserId
                )
            ) {
                UserIdentityRowView(
                    user: user,
                    subtitle: memberSubtitle,
                    avatarSize: 50
                )
            }
            .accessibilityLabel("\(user.displayName), @\(user.userName), \(memberSubtitle)")
            .task {
                publicLifetimeStatsRepository.ensureObservingFriend(userId: member.userId)
            }
        } else {
            HStack {
                AvatarImageView(avatarId: nil, size: 50)
                    .accessibleDecorative()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Member".localized)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                    Text(member.roleEnum.displayName)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown.opacity(0.7))
                }
                Spacer()
            }
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\("Member".localized), \(member.roleEnum.displayName)")
        }
    }
}

struct PendingRequestRow: View {
    let request: PendingJoinRequest
    @State private var resolvedUser: AppUser?

    private var displayUser: AppUser? {
        request.user ?? resolvedUser
    }
    
    var body: some View {
        Group {
            if let user = displayUser {
                UserDetailNavigationLink(user: user) {
                    UserIdentityRowView(
                        user: user,
                        subtitle: "Pending".localized,
                        avatarSize: 50
                    )
                }
                .accessibilityLabel(pendingRequestAccessibilityLabel)
            } else {
                HStack {
                    AvatarImageView(avatarId: nil, size: 50)
                    VStack(alignment: .leading) {
                        Text("Pending User".localized)
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.Theme.primaryBlue)
                        
                        Text("Waiting for approval".localized)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(pendingRequestAccessibilityLabel)
            }
        }
        .task(id: request.userId) {
            await resolveUserIfNeeded()
        }
    }

    private var pendingRequestAccessibilityLabel: String {
        if let user = displayUser {
            return "\(user.displayName), @\(user.userName), \("Pending".localized)"
        }
        return "Pending User".localized
    }

    private func resolveUserIfNeeded() async {
        if request.user != nil {
            await MainActor.run { resolvedUser = nil }
            return
        }
        do {
            if let fetched = try await UserRepository.shared.getUser(userId: request.userId) {
                await MainActor.run {
                    self.resolvedUser = fetched
                }
            }
        } catch {
            #if DEBUG
            print("⚠️ PendingRequestRow failed to resolve user \(request.userId): \(error.localizedDescription)")
            #endif
        }
    }
}

#Preview {
    FamilyDashboard()
        .environmentObject(FirebaseAuthService())
        .modelContainer(for: [Family.self, FamilyMember.self], inMemory: true)
}

