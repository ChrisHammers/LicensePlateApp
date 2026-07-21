//
//  FamilySettings.swift
//  LicensePlateApp
//
//  Created for Friends & Family MVP
//

import SwiftUI
import SwiftData

struct FamilySettings: View {
    let familyId: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authService: FirebaseAuthService
    @StateObject private var viewModel: FamilySettingsViewModel
    @State private var showLeaveFamilyConfirmation = false
    @State private var showDeleteFamilyConfirmation = false
    
    init(familyId: String) {
        self.familyId = familyId
        let familyRepo = FamilyRepository.shared
        _viewModel = StateObject(wrappedValue: FamilySettingsViewModel(
            familyRepository: familyRepo,
            authService: FirebaseAuthService()
        ))
    }
    
    var body: some View {
        NavigationStack {
            AppBackgroundView {
                List {
                    // Family Name
                    if viewModel.isCaptainOrCreator {
                        Section("Family Name".localized) {
                            HStack(spacing: 12) {
                                FamilyInitialAvatarView(
                                    familyName: viewModel.familyName.isEmpty ? "?" : viewModel.familyName,
                                    size: 44
                                )
                                .accessibilityHidden(true)
                                SettingEditableTextRow(
                                    title: "Name".localized,
                                    value: $viewModel.familyName,
                                    placeholder: "Enter family name".localized,
                                    detail: nil,
                                    isDisabled: viewModel.isSavingName || !authService.isOnline,
                                    onSave: {
                                        viewModel.saveFamilyName()
                                    },
                                    onCancel: {
                                        viewModel.cancelFamilyNameEditing()
                                    }
                                )
                            }
                        }
                        .listRowBackground(Color.Theme.cardBackground)
                    } else if !viewModel.familyName.isEmpty {
                        Section("Family Name".localized) {
                            HStack(spacing: 12) {
                                FamilyInitialAvatarView(familyName: viewModel.familyName, size: 44)
                                    .accessibilityHidden(true)
                                Text(viewModel.familyName)
                                    .font(.system(.body, design: .rounded))
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.Theme.primaryBlue)
                                Spacer(minLength: 0)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(viewModel.familyName)
                        }
                        .listRowBackground(Color.Theme.cardBackground)
                    }
                    
                    // Members
                    Section("Members".localized) {
                        ForEach(viewModel.members) { member in
                            FamilyMemberSettingsRow(member: member)
                        }
                    }
                    .listRowBackground(Color.Theme.cardBackground)
                    
                    // Leave Family (All members except creator)
                    if !viewModel.isCreator {
                        Section {
                            Button(role: .destructive) {
                                showLeaveFamilyConfirmation = true
                            } label: {
                                Text("Leave Family".localized)
                                    .foregroundColor(.red)
                            }
                            .accessibleButton(label: "Leave Family".localized)
                        } header: {
                            Text("Leave Family".localized)
                        } footer: {
                            Text("You will be removed from this family and will need to be invited again to rejoin.".localized)
                        }
                        .listRowBackground(Color.Theme.cardBackground)
                    }
                    
                    // Danger Zone (Creator only)
                    if viewModel.isCreator {
                        Section {
                            Button(role: .destructive) {
                                showDeleteFamilyConfirmation = true
                            } label: {
                                if viewModel.isDeletingFamily {
                                    HStack {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                        Text("Deleting...".localized)
                                    }
                                } else {
                                    Text("Delete Family".localized)
                                }
                            }
                            .foregroundColor(.red)
                            .disabled(viewModel.isDeletingFamily)
                            .accessibleButton(
                                label: viewModel.isDeletingFamily
                                    ? "Deleting...".localized
                                    : "Delete Family".localized
                            )
                        } header: {
                            Text("Danger Zone".localized)
                        } footer: {
                            Text("This will permanently delete the family and remove all members. This action cannot be undone.".localized)
                        }
                        .listRowBackground(Color.Theme.cardBackground)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Family Settings".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done".localized) {
                        dismiss()
                    }
                }
            }
            .onAppear {
                viewModel.setModelContext(modelContext)
                viewModel.setAuthService(authService)
                viewModel.loadData(familyId: familyId)
            }
            .onChange(of: viewModel.didLeaveOrDelete) { _, didLeave in
                if didLeave { dismiss() }
            }
            .alert("Leave Family".localized, isPresented: $showLeaveFamilyConfirmation) {
                Button("Cancel".localized, role: .cancel) {}
                Button("Leave".localized, role: .destructive) {
                    viewModel.leaveFamily()
                }
            } message: {
                Text("Are you sure you want to leave this family? You will need to be invited again to rejoin.".localized)
            }
            .alert("Error".localized, isPresented: $viewModel.showErrorAlert) {
                Button("OK".localized) {
                    viewModel.errorMessage = nil
                }
            } message: {
                if let error = viewModel.errorMessage {
                    Text(error)
                }
            }
            .alert("Delete Family".localized, isPresented: $showDeleteFamilyConfirmation) {
                Button("Cancel".localized, role: .cancel) {}
                Button("Delete".localized, role: .destructive) {
                    viewModel.deleteFamily()
                }
            } message: {
                Text("Are you sure you want to delete this family? This will permanently remove the family and all its members. This action cannot be undone.".localized)
            }
        }
    }
}

struct FamilyMemberSettingsRow: View {
    let member: FamilyMember
    
    var body: some View {
        HStack {
            if let user = member.user {
                AvatarImageView(user: user, size: 40)
            } else {
                AvatarImageView(avatarId: nil, size: 40)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(member.user?.displayName ?? "Member".localized)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.Theme.primaryBlue)
                
                if let userName = member.user?.userName {
                    Text("@\(userName)")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                }
                
                Text(member.roleEnum.displayName)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown.opacity(0.7))
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(settingsMemberAccessibilityLabel)
    }

    private var settingsMemberAccessibilityLabel: String {
        if let user = member.user {
            return "\(user.displayName), @\(user.userName), \(member.roleEnum.displayName)"
        }
        return "\("Member".localized), \(member.roleEnum.displayName)"
    }
}

#Preview {
    FamilySettings(familyId: "test")
        .environmentObject(FirebaseAuthService())
}

