//
//  InviteToFamilyView.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import SwiftUI
import SwiftData

struct InviteToFamilyView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authService: FirebaseAuthService
    var family: Family?
    
    @State private var selectedRole: FamilyMember.FamilyRole = .sergeant
    @State private var invitationMethod: InvitationMethod = .shareCode
    @State private var shareCode: String = ""
    @State private var searchText: String = ""
    @State private var showRoleSelection = true
    
    enum InvitationMethod {
        case shareCode
        case inAppSearch
    }
    
    var currentUser: AppUser? {
        authService.currentUser
    }
    
    var isCreatingNewFamily: Bool {
        family == nil
    }
    
    var body: some View {
        NavigationStack {
            AppBackgroundView {
                Form {
                    if isCreatingNewFamily {
                        Section {
                            Text("Create a new family or join an existing one using a share code.".localized)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .textCase(nil)
                    }
                    
                    // Role Selection
                    if showRoleSelection {
                        Section("Select Role".localized) {
                            Picker("Role".localized, selection: $selectedRole) {
                                ForEach(FamilyMember.FamilyRole.allCases, id: \.self) { role in
                                    Text(role.displayName).tag(role)
                                }
                            }
                            .pickerStyle(.menu)
                            
                            Text(roleDescription(for: selectedRole))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .textCase(nil)
                    }
                    
                    // Create Family Button (only when creating new family)
                    if isCreatingNewFamily {
                        Section {
                            Button {
                                createNewFamily()
                            } label: {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Create New Family".localized)
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.Theme.primaryBlue)
                                .foregroundStyle(.white)
                                .cornerRadius(12)
                            }
                        }
                        .textCase(nil)
                    }
                    
                    // Invitation Method (only show when joining or inviting to existing family)
                    if !isCreatingNewFamily {
                        Section("Invitation Method".localized) {
                            Picker("Method".localized, selection: $invitationMethod) {
                                Text("Share Code".localized).tag(InvitationMethod.shareCode)
                                Text("Search User".localized).tag(InvitationMethod.inAppSearch)
                            }
                            .pickerStyle(.segmented)
                        }
                        .textCase(nil)
                    } else {
                        // When creating, show join options
                        Section("Or Join Existing Family".localized) {
                            Picker("Method".localized, selection: $invitationMethod) {
                                Text("Share Code".localized).tag(InvitationMethod.shareCode)
                                Text("Search User".localized).tag(InvitationMethod.inAppSearch)
                            }
                            .pickerStyle(.segmented)
                        }
                        .textCase(nil)
                    }
                    
                    // Share Code Method
                    if invitationMethod == .shareCode {
                        Section {
                            if let family = family {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Family Share Code".localized)
                                        .font(.headline)
                                    
                                    if shareCode.isEmpty {
                                        Button {
                                            generateShareCode()
                                        } label: {
                                            Text("Generate Share Code".localized)
                                        }
                                    } else {
                                        HStack {
                                            Text(shareCode)
                                                .font(.title2)
                                                .fontWeight(.bold)
                                                .fontDesign(.monospaced)
                                            
                                            Button {
                                                UIPasteboard.general.string = shareCode
                                            } label: {
                                                Image(systemName: "doc.on.doc")
                                            }
                                        }
                                        
                                        Text("Share this code with others to invite them to your family.".localized)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Enter Share Code".localized)
                                        .font(.headline)
                                    
                                    TextField("Enter code".localized, text: $shareCode)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                    
                                    Button {
                                        joinFamilyWithCode()
                                    } label: {
                                        Text("Join Family".localized)
                                    }
                                    .disabled(shareCode.isEmpty)
                                }
                            }
                        }
                        .textCase(nil)
                    }
                    
                    // In-App Search Method
                    if invitationMethod == .inAppSearch {
                        Section {
                            TextField("Search by username or email".localized, text: $searchText)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            
                            if !searchText.isEmpty {
                                Button {
                                    searchAndInviteUser()
                                } label: {
                                    Text("Search and Invite".localized)
                                }
                            }
                        }
                        .textCase(nil)
                    }
                }
                .scrollContentBackground(.hidden)
                .navigationTitle(isCreatingNewFamily ? "Create or Join Family".localized : "Invite to Family".localized)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            dismiss()
                        } label: {
                            Text("Cancel".localized)
                        }
                    }
                }
            }
        }
    }
    
    private func roleDescription(for role: FamilyMember.FamilyRole) -> String {
        switch role {
        case .captain:
            return "Full family management, can approve friend requests for Scouts".localized
        case .sergeant:
            return "Full participation, can create trips/games".localized
        case .scout:
            return "Mark-only permissions in shared trips, friend requests require Captain approval".localized
        case .retiredGeneral:
            return "Sergeant-level permissions, can be in multiple families".localized
        }
    }
    
    private func generateShareCode() {
        shareCode = UUID().uuidString.prefix(8).uppercased()
        // In a real implementation, this would be stored in the family model
    }
    
    private func joinFamilyWithCode() {
        // In a real implementation, this would search for a family with this share code
        // For now, just dismiss
        dismiss()
    }
    
    private func searchAndInviteUser() {
        // In a real implementation, this would search for users and send invitations
        // For now, just dismiss
        dismiss()
    }
    
    private func createNewFamily() {
        guard let userID = currentUser?.id else {
            dismiss()
            return
        }
        
        // Create new family
        let newFamily = Family(
            name: nil, // Can be set later
            createdAt: .now,
            lastUpdated: .now
        )
        
        // Add current user as Captain
        let captainMember = FamilyMember(
            userID: userID,
            familyID: newFamily.id,
            role: .captain,
            joinedAt: .now,
            invitedBy: nil,
            isActive: true
        )
        
        newFamily.members.append(captainMember)
        
        // Update user's familyID
        currentUser?.familyID = newFamily.id
        
        // Save to model context
        modelContext.insert(newFamily)
        modelContext.insert(captainMember)
        
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Error creating family: \(error)")
            dismiss()
        }
    }
}

