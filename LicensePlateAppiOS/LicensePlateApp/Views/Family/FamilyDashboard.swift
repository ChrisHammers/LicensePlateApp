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
                                FamilyMemberRow(
                                    member: member,
                                    familyCreatorId: family.creatorId,
                                    isChild: viewModel.isChildMember(memberId: member.userId)
                                )
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

                        // Outgoing invites waiting for invitee response (visible to all members)
                        if !viewModel.outgoingPendingInvites.isEmpty {
                            Section("Waiting for response".localized) {
                                ForEach(viewModel.outgoingPendingInvites) { invite in
                                    FamilyOutgoingInviteRow(invite: invite)
                                }
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
                    // No active family — awaiting captain approval, or create/join options
                    let isAwaitingApproval = viewModel.awaitingApprovalInvite != nil
                    VStack(spacing: 24) {
                        Spacer()
                        
                        VStack(spacing: 12) {
                            Image(systemName: isAwaitingApproval ? "hourglass.circle.fill" : "house.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(Color.Theme.primaryBlue.opacity(0.6))
                                .accessibleDecorative()
                            
                            if let invite = viewModel.awaitingApprovalInvite {
                                let familyName: String? = {
                                    let name = invite.familyName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                                    return name.isEmpty ? nil : name
                                }()
                                Text(
                                    familyName.map { "family.awaiting_approval.title".localized($0) }
                                        ?? "Family".localized
                                )
                                    .font(.system(.title2, design: .rounded))
                                    .fontWeight(.bold)
                                    .foregroundStyle(Color.Theme.primaryBlue)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 32)
                                    .padding(.bottom, 15)
                                
                                Text(
                                    familyName.map { "family.awaiting_approval.request".localized($0) }
                                        ?? "family.awaiting_approval.request_generic".localized
                                )
                                    .font(.system(.body, design: .rounded))
                                    .foregroundStyle(Color.Theme.softBrown)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 32)
                                
                                Text("Waiting for Captain approval".localized)
                                    .font(.system(.subheadline, design: .rounded))
                                    .foregroundStyle(Color.Theme.softBrown.opacity(0.9))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 32)
                                    .padding(.bottom, 35)
                            } else {
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
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(
                            isAwaitingApproval
                                ? {
                                    let name = viewModel.awaitingApprovalInvite?.familyName?
                                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                                    return name.isEmpty
                                        ? "family.a11y.awaiting_approval_generic".localized
                                        : "family.a11y.awaiting_approval".localized(name)
                                }()
                                : "family.a11y.empty_state".localized
                        )
                        
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
                                .background(Color.Theme.primaryBlue.opacity(isAwaitingApproval ? 0.45 : 1))
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                            .disabled(!authService.isOnline || isAwaitingApproval)
                            .accessibleButton(
                                label: "family.a11y.create_family".localized,
                                hint: isAwaitingApproval
                                    ? "family.a11y.awaiting_approval_actions_disabled".localized
                                    : nil
                            )
                            
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
                                .foregroundColor(
                                    Color.Theme.primaryBlue.opacity(isAwaitingApproval ? 0.45 : 1)
                                )
                                .cornerRadius(12)
                            }
                            .disabled(!authService.isOnline || isAwaitingApproval)
                            .accessibleButton(
                                label: "family.a11y.join_family".localized,
                                hint: isAwaitingApproval
                                    ? "family.a11y.awaiting_approval_actions_disabled".localized
                                    : nil
                            )
                        }
                        .padding(.horizontal, 32)
                        
                        if isAwaitingApproval {
                            Text("family.awaiting_approval.actions_locked".localized)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(Color.Theme.softBrown)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        } else if !authService.isOnline {
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
                
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        if viewModel.family != nil {
                            Button {
                                showSettings = true
                            } label: {
                                Image(systemName: "gearshape")
                                    .foregroundStyle(Color.Theme.primaryBlue)
                            }
                            .accessibleButton(
                                label: "Family Settings".localized,
                                hint: viewModel.canManageFamily
                                    ? "family.a11y.opens_settings".localized
                                    : "family.a11y.opens_settings_member".localized
                            )
                        }
                        if viewModel.canManageFamily, viewModel.pendingMemberRequestsCount > 0 {
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
       // }
    }
}

struct FamilyMemberRow: View {
    let member: FamilyMember
    let familyCreatorId: String?
    /// COPPA FR-20: read-only `members/{uid}.isChild` projection supplied by the view
    /// model. The dashboard shows the badge only — every manage control lives in
    /// Family Settings behind the creator/captain gate.
    var isChild: Bool = false
    @EnvironmentObject private var authService: FirebaseAuthService

    private var rolePresentation: FamilyMemberRolePresentation {
        FamilyMemberRolePresentation.make(
            role: member.roleEnum,
            memberUserId: member.userId,
            familyCreatorId: familyCreatorId
        )
    }

    private var currentUserId: String? {
        authService.currentUser?.firebaseUID ?? authService.currentUser?.id
    }

    /// FR-22: status reaches VoiceOver as text, never as a color-only cue.
    private var childAccessibilitySuffix: String {
        isChild ? ", \("family.child.a11y.badge".localized)" : ""
    }

    var body: some View {
        if let user = member.user {
            let isSelf = UserDetailNavigation.isSelfProfile(
                user: user,
                currentUserId: currentUserId
            )
            let decoratedName = ParticipantDisplayName.decorated(
                user.displayName,
                isCurrentUser: isSelf
            )
            UserDetailNavigationLink(
                user: user,
                isSelfProfile: isSelf
            ) {
                HStack(spacing: 8) {
                    UserIdentityRowView(
                        user: user,
                        subtitle: rolePresentation.roleText,
                        avatarSize: 50,
                        isCurrentUser: isSelf
                    )
                    if isChild {
                        FamilyChildBadge()
                    }
                    if rolePresentation.showsCreatorBadge {
                        FamilyCreatorBadge()
                    }
                }
            }
            .accessibilityLabel(
                "\(decoratedName), @\(user.userName), \(rolePresentation.accessibilityText)\(childAccessibilitySuffix)"
            )
        } else {
            HStack {
                AvatarImageView(avatarId: nil, size: 50)
                    .accessibleDecorative()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Member".localized)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                    Text(rolePresentation.roleText)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown.opacity(0.7))
                }
                Spacer()
                if isChild {
                    FamilyChildBadge()
                }
                if rolePresentation.showsCreatorBadge {
                    FamilyCreatorBadge()
                }
            }
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "\("Member".localized), \(rolePresentation.accessibilityText)\(childAccessibilitySuffix)"
            )
        }
    }
}

private struct FamilyOutgoingInviteRow: View {
    let invite: Invite
    @State private var resolvedUser: AppUser?

    private var displayUser: AppUser? {
        resolvedUser
    }

    private var inviteeUserId: String? {
        invite.toUserId
    }

    var body: some View {
        Group {
            if let user = displayUser {
                UserDetailNavigationLink(user: user) {
                    UserIdentityRowView(
                        user: user,
                        subtitle: "Waiting for response".localized,
                        avatarSize: 50
                    )
                }
                .accessibilityLabel(outgoingInviteAccessibilityLabel)
            } else {
                HStack {
                    AvatarImageView(avatarId: nil, size: 50)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pending User".localized)
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.Theme.primaryBlue)

                        Text("Waiting for response".localized)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(outgoingInviteAccessibilityLabel)
            }
        }
        .task(id: inviteeUserId) {
            await resolveUserIfNeeded()
        }
    }

    private var outgoingInviteAccessibilityLabel: String {
        if let user = displayUser {
            return "family.a11y.outgoing_invite".localized(user.displayName, user.userName)
        }
        return "family.a11y.outgoing_invite_unknown".localized
    }

    private func resolveUserIfNeeded() async {
        guard let inviteeUserId else { return }
        do {
            if let fetched = try await UserRepository.shared.getUser(userId: inviteeUserId) {
                await MainActor.run {
                    self.resolvedUser = fetched
                }
            }
        } catch {
            #if DEBUG
            print("⚠️ FamilyOutgoingInviteRow failed to resolve user \(inviteeUserId): \(error.localizedDescription)")
            #endif
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

