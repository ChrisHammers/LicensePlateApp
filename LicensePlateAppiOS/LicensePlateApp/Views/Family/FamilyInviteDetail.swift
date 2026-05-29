//
//  FamilyInviteDetail.swift
//  LicensePlateApp
//
//  Created for Friends & Family MVP
//

import SwiftUI
import SwiftData

struct FamilyInviteDetail: View {
    let inviteId: String
    let familyId: String
    let family: Family? // Optional - passed from parent if available
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authService: FirebaseAuthService
    private let familyRepository = FamilyRepository.shared
    @StateObject private var viewModel: FamilyInviteDetailViewModel
    @State private var loadedFamily: Family?
    @State private var captains: [FamilyMember] = []
    @State private var isLoadingFamily = false

    init(inviteId: String, familyId: String, family: Family?) {
        self.inviteId = inviteId
        self.familyId = familyId
        self.family = family
        _viewModel = StateObject(wrappedValue: FamilyInviteDetailViewModel(inviteId: inviteId, familyId: familyId))
    }
    
    // Computed property to use passed family or loaded family
    private var displayFamily: Family? {
        family ?? loadedFamily
    }
    
    var body: some View {
        NavigationStack {
            AppBackgroundView {
                ScrollView {
                    VStack(spacing: 24) {
                        // Family Name Section
                        if isLoadingFamily && displayFamily == nil {
                            ProgressView()
                                .padding()
                        } else if let family = displayFamily {
                            VStack(spacing: 12) {
                                Text("You've been invited to join".localized)
                                    .font(.system(.subheadline, design: .rounded))
                                    .foregroundStyle(Color.Theme.softBrown)
                                
                                Text(family.name)
                                    .font(.system(.title, design: .rounded))
                                    .fontWeight(.bold)
                                    .foregroundStyle(Color.Theme.primaryBlue)
                                    .multilineTextAlignment(.center)
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.Theme.cardBackground)
                            .cornerRadius(16)
                            
                            // Captains Section
                            if !captains.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Captains".localized)
                                        .font(.system(.headline, design: .rounded))
                                        .foregroundStyle(Color.Theme.primaryBlue)
                                    
                                    ForEach(captains) { captain in
                                        HStack {
                                            Circle()
                                                .fill(Color.Theme.primaryBlue.opacity(0.3))
                                                .frame(width: 40, height: 40)
                                            
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(captain.user?.displayName ?? "Captain".localized)
                                                    .font(.system(.body, design: .rounded))
                                                    .fontWeight(.semibold)
                                                    .foregroundStyle(Color.Theme.primaryBlue)
                                                
                                                if let userName = captain.user?.userName {
                                                    Text("@\(userName)")
                                                        .font(.system(.caption, design: .rounded))
                                                        .foregroundStyle(Color.Theme.softBrown)
                                                }
                                            }
                                            
                                            Spacer()
                                            
                                            Text(captain.roleEnum == .creator ? "Creator".localized : "Captain".localized)
                                                .font(.system(.caption, design: .rounded))
                                                .foregroundStyle(Color.Theme.softBrown)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.Theme.cardBackground)
                                                .cornerRadius(8)
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.Theme.cardBackground)
                                .cornerRadius(16)
                            }
                        } else {
                            Text("Family Invitation".localized)
                                .font(.system(.title2, design: .rounded))
                                .fontWeight(.bold)
                                .foregroundStyle(Color.Theme.primaryBlue)
                        }
                        
                        if viewModel.hasAccepted {
                        VStack(spacing: 12) {
                            Text("Waiting for Captain approval".localized)
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(Color.Theme.softBrown)
                            
                            Text("A family captain will review your request".localized)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(Color.Theme.softBrown.opacity(0.7))
                        }
                        .padding()
                    } else {
                        Button {
                            viewModel.respondToInvite(accept: true, onDeclineDismiss: { })
                        } label: {
                            Text("Accept".localized)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.Theme.primaryBlue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        .disabled(viewModel.isProcessing || !authService.isOnline)
                        
                        Button {
                            viewModel.respondToInvite(accept: false, onDeclineDismiss: { dismiss() })
                        } label: {
                            Text("Decline".localized)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.Theme.cardBackground)
                                .foregroundColor(Color.Theme.primaryBlue)
                                .cornerRadius(12)
                        }
                        .disabled(viewModel.isProcessing || !authService.isOnline)
                    }
                    
                    if !authService.isOnline {
                        Text("Requires network connection".localized)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                    }
                    
                        if let error = viewModel.errorMessage {
                            Text(error)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.red)
                                .padding(.top, 8)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Family Invite".localized)
            .navigationBarTitleDisplayMode(.inline)
            .alert("Error".localized, isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK".localized, role: .cancel) { viewModel.errorMessage = nil }
            } message: {
                if let error = viewModel.errorMessage {
                    Text(error)
                }
            }
            .onAppear {
                familyRepository.setModelContext(modelContext)
                viewModel.configure(authService: authService, modelContext: modelContext)
                loadFamilyData()
            }
        }
    }
    
    private func loadFamilyData() {
        // If family is already passed in, we still need to load members
        // But we can skip loading family if it's already provided
        if family == nil {
            isLoadingFamily = true
        }
        
        Task {
            do {
                // Only fetch family if not already provided
                var fetchedFamily: Family?
                if family == nil {
                    fetchedFamily = try await familyRepository.fetchFamily(familyId: familyId)
                }
                
                // Always fetch members to get captains
                let fetchedMembers = try await familyRepository.fetchMembers(familyId: familyId)
                
                // Filter for captains and creator
                let captainsList = fetchedMembers.filter { member in
                    member.roleEnum == .captain || member.roleEnum == .creator
                }
                
                await MainActor.run {
                    if let fetchedFamily = fetchedFamily {
                        loadedFamily = fetchedFamily
                    }
                    captains = captainsList
                    isLoadingFamily = false
                }
            } catch {
                await MainActor.run {
                    isLoadingFamily = false
                    print("❌ Failed to load family data: \(error.localizedDescription)")
                    // Don't show error to user - just show generic invitation
                }
            }
        }
    }
    
}

#Preview {
    FamilyInviteDetail(inviteId: "test", familyId: "test", family: nil)
        .environmentObject(FirebaseAuthService())
}

