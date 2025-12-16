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
    
    init() {
        let familyRepo = FamilyRepository()
        _viewModel = StateObject(wrappedValue: FamilyDashboardViewModel(
            familyRepository: familyRepo,
            authService: FirebaseAuthService()
        ))
    }
    
    var body: some View {
        NavigationStack {
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
                                
                                Text("Your crew".localized)
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
                        }
                        
                        // Pending
                        if !viewModel.pendingRequests.isEmpty {
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
                    VStack {
                        Text("No active family".localized)
                            .foregroundStyle(Color.Theme.softBrown)
                    }
                }
            }
            .navigationTitle("Family".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if viewModel.canManageFamily {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                                .foregroundStyle(Color.Theme.primaryBlue)
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
            .onAppear {
                viewModel.setModelContext(modelContext)
                viewModel.loadData()
                AnalyticsService.shared.log(.familyScreenOpened)
            }
        }
    }
}

struct FamilyMemberRow: View {
    let member: FamilyMember
    
    var body: some View {
        HStack {
            Circle()
                .fill(Color.Theme.primaryBlue.opacity(0.3))
                .frame(width: 50, height: 50)
            
            VStack(alignment: .leading) {
                Text(member.user?.displayName ?? "Member")
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                
                Text(member.roleEnum.displayName)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

struct PendingRequestRow: View {
    let request: PendingJoinRequest
    
    var body: some View {
        HStack {
            Circle()
                .fill(Color.Theme.primaryBlue.opacity(0.3))
                .frame(width: 50, height: 50)
            
            VStack(alignment: .leading) {
                Text(request.user?.displayName ?? "Pending User")
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

#Preview {
    FamilyDashboard()
        .environmentObject(FirebaseAuthService())
        .modelContainer(for: [Family.self, FamilyMember.self], inMemory: true)
}

