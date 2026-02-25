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
    @State private var isProcessing = false
    @State private var hasAccepted = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var loadedFamily: Family?
    @State private var captains: [FamilyMember] = []
    @State private var isLoadingFamily = false
    
    // Computed property to use passed family or loaded family
    private var displayFamily: Family? {
        family ?? loadedFamily
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.Theme.background
                    .ignoresSafeArea()
                
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
                        
                        if hasAccepted {
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
                            respondToInvite(accept: true)
                        } label: {
                            Text("Accept".localized)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.Theme.primaryBlue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        .disabled(isProcessing || !authService.isOnline)
                        
                        Button {
                            respondToInvite(accept: false)
                        } label: {
                            Text("Decline".localized)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.gray.opacity(0.2))
                                .foregroundColor(Color.Theme.primaryBlue)
                                .cornerRadius(12)
                        }
                        .disabled(isProcessing || !authService.isOnline)
                    }
                    
                    if !authService.isOnline {
                        Text("Requires network connection".localized)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                    }
                    
                        if let error = errorMessage {
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
            .alert("Error".localized, isPresented: $showError) {
                Button("OK".localized, role: .cancel) { }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
            }
            .onAppear {
                familyRepository.setModelContext(modelContext)
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
    
    private func respondToInvite(accept: Bool) {
        guard authService.isOnline else {
            errorMessage = "Requires network connection".localized
            showError = true
            return
        }
        
        isProcessing = true
        errorMessage = nil
        
        Task {
            do {
                try await familyRepository.respondToFamilyInvite(inviteId: inviteId, accept: accept)
                
                await MainActor.run {
                    isProcessing = false
                    if accept {
                        hasAccepted = true
                        AnalyticsService.shared.log(.familyInviteUserAccepted)
                    } else {
                        AnalyticsService.shared.log(.familyInviteUserDeclined)
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    errorMessage = error.localizedDescription
                    showError = true
                    if !accept {
                        // If declining failed, still dismiss
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    FamilyInviteDetail(inviteId: "test", familyId: "test", family: nil)
        .environmentObject(FirebaseAuthService())
}

