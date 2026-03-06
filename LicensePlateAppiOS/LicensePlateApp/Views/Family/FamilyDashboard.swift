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
            authService: tempAuthService
        ))
    }
    
    var body: some View {
     //   NavigationStack {
            ZStack {
                Color.Theme.background
                    .ignoresSafeArea()
                
                if viewModel.isLoading {
                    ProgressView()
                } else if let family = viewModel.family {
                    List {
                        // Header
                        Section {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(family.name)
                                    .font(.system(.title, design: .rounded))
                                    .fontWeight(.bold)
                                    .foregroundStyle(Color.Theme.primaryBlue)
                                
                                Text("Your family".localized)
                                    .font(.system(.subheadline, design: .rounded))
                                    .foregroundStyle(Color.Theme.softBrown)
                            }
                            .padding(.vertical, 8)
                        }
                        
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
                                        Text("Invite a Family Member".localized)
                                    }
                                    .font(.system(.body, design: .rounded))
                                    .foregroundStyle(Color.Theme.primaryBlue)
                                }
                                .disabled(!authService.isOnline)
                                
                                Button {
                                    showCreateShareCodeSheet = true
                                } label: {
                                    HStack {
                                        Image(systemName: "qrcode")
                                        Text(viewModel.shareCodeButtonText)
                                    }
                                    .font(.system(.body, design: .rounded))
                                    .foregroundStyle(Color.Theme.primaryBlue)
                                }
                                .disabled(!authService.isOnline)
                            }
                        }
                        
                        // Pending Invites Section
                        if viewModel.pendingFamilyInvitesCount > 0 {
                            Section {
                                Button {
                                    showFamilyInvitesView = true
                                } label: {
                                    HStack {
                                        Image(systemName: "envelope.fill")
                                            .foregroundStyle(Color.Theme.primaryBlue)
                                        Text("Pending Invites".localized)
                                            .font(.system(.body, design: .rounded))
                                            .foregroundStyle(Color.Theme.primaryBlue)
                                        Spacer()
                                        BadgeView(count: viewModel.pendingFamilyInvitesCount)
                                    }
                                }
                            }
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
                        } else if !viewModel.pendingRequests.isEmpty {
                            Section("Pending".localized) {
                                ForEach(viewModel.pendingRequests) { request in
                                    PendingRequestRow(request: request)
                                }
                            }
                        }
                        
                        // Stats placeholder
                        Section("Family Stats".localized) {
                            HStack {
                                Text("Total Trips: 0")
                                Spacer()
                                Text("Total Finds: 0")
                            }
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
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
                        
                        VStack(spacing: 16) {
                            Button {
                                showCreateFamilySheet = true
                            } label: {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
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
                            
                            Button {
                                showJoinFamilySheet = true
                            } label: {
                                HStack {
                                    Image(systemName: "person.2.badge.plus")
                                    Text("Join Family".localized)
                                }
                                .font(.system(.body, design: .rounded))
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.gray.opacity(0.2))
                                .foregroundColor(Color.Theme.primaryBlue)
                                .cornerRadius(12)
                            }
                            .disabled(!authService.isOnline)
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
                                .badge(count: viewModel.pendingFamilyInvitesCount)
                        }
                    }
                }
                
                if viewModel.canManageFamily {
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 16) {
                            if viewModel.pendingMemberRequestsCount > 0 {
                                Button {
                                    showPendingApprovalsView = true
                                } label: {
                                    Image(systemName: "person.badge.clock")
                                        .foregroundStyle(Color.Theme.primaryBlue)
                                        .badge(count: viewModel.pendingMemberRequestsCount)
                                }
                            }
                            
                            Button {
                                showSettings = true
                            } label: {
                                Image(systemName: "gearshape")
                                    .foregroundStyle(Color.Theme.primaryBlue)
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
                viewModel.loadData()
                AnalyticsService.shared.log(.familyScreenOpened)
                
                // Start listening to invites for badge counts
                if let userId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id {
                    // InviteRepository will be set up in ViewModel
                }
            }
            .onDisappear {
                // Stop listening when view disappears to prevent permission errors
                FamilyRepository.shared.stopListening()
            }
       // }
    }
}

struct FamilyMemberRow: View {
    let member: FamilyMember
    
    var body: some View {
        if let user = member.user {
            UserIdentityRowView(
                user: user,
                subtitle: member.roleEnum.displayName,
                avatarSize: 50
            )
        } else {
            HStack {
                Circle()
                    .fill(Color.Theme.primaryBlue.opacity(0.3))
                    .frame(width: 50, height: 50)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Member")
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
        }
    }
}

struct PendingRequestRow: View {
    let request: PendingJoinRequest
    
    var body: some View {
        if let user = request.user {
            UserIdentityRowView(
                user: user,
                subtitle: "Pending",
                avatarSize: 50
            )
        } else {
            HStack {
                Circle()
                    .fill(Color.Theme.primaryBlue.opacity(0.3))
                    .frame(width: 50, height: 50)
                VStack(alignment: .leading) {
                    Text("Pending User")
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
        }
    }
}

#Preview {
    FamilyDashboard()
        .environmentObject(FirebaseAuthService())
        .modelContainer(for: [Family.self, FamilyMember.self], inMemory: true)
}

