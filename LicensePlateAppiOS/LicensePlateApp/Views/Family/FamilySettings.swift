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
                        
                        // Members
                        Section("Members".localized) {
                            ForEach(viewModel.members) { member in
                                FamilyMemberSettingsRow(
                                    member: member,
                                    familyCreatorId: viewModel.family?.creatorId
                                )
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    if viewModel.canRemove(memberId: member.userId) {
                                        Button(role: .destructive) {
                                            viewModel.confirmRemoveMember(memberId: member.userId)
                                        } label: {
                                            Label("Remove".localized, systemImage: "person.fill.xmark")
                                        }
                                        .disabled(viewModel.isRemovingMember)
                                    }
                                }
                            }
                        }
                        .listRowBackground(Color.Theme.cardBackground)

                    }

                    
                    // Leave Family (All members except creator)
                    if !viewModel.isCreator {
                        Section {
                            Button(role: .destructive) {
                                showLeaveFamilyConfirmation = true
                            } label: {
                                if viewModel.isLeavingFamily {
                                    HStack {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                        Text("Leaving...".localized)
                                    }
                                } else {
                                    Text("Leave Family".localized)
                                        .foregroundColor(.red)
                                }
                            }
                            .disabled(viewModel.isLeavingFamily)
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
            .alert(
                "Remove Family Member".localized,
                isPresented: Binding(
                    get: { viewModel.memberIdPendingRemoval != nil },
                    set: { if !$0 { viewModel.cancelRemoveMember() } }
                )
            ) {
                Button("Cancel".localized, role: .cancel) {
                    viewModel.cancelRemoveMember()
                }
                Button("Remove".localized, role: .destructive) {
                    viewModel.removePendingMember()
                }
            } message: {
                Text("They will be removed from this family and must be invited again to rejoin.".localized)
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
    let familyCreatorId: String?
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

    private var isSelfMember: Bool {
        guard let user = member.user else {
            return member.userId == currentUserId
        }
        return UserDetailNavigation.isSelfProfile(user: user, currentUserId: currentUserId)
    }

    private func decoratedMemberName(for user: AppUser?) -> String {
        let raw = user?.displayName ?? "Member".localized
        guard user != nil else { return raw }
        return ParticipantDisplayName.decorated(raw, isCurrentUser: isSelfMember)
    }

    var body: some View {
        if let user = member.user {
            UserDetailNavigationLink(
                user: user,
                isSelfProfile: isSelfMember
            ) {
                settingsRowContent(user: user)
            }
            .padding(.vertical, 8)
            .accessibilityLabel(settingsMemberAccessibilityLabel)
        } else {
            settingsRowContent(user: nil)
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(settingsMemberAccessibilityLabel)
        }
    }

    private func settingsRowContent(user: AppUser?) -> some View {
        HStack {
            if let user {
                AvatarImageView(user: user, size: 40)
            } else {
                AvatarImageView(avatarId: nil, size: 40)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(decoratedMemberName(for: user))
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.Theme.primaryBlue)

                if let userName = user?.userName {
                    Text("@\(userName)")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                }

                Text(rolePresentation.roleText)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown.opacity(0.7))
            }

            Spacer()

            if rolePresentation.showsCreatorBadge {
                FamilyCreatorBadge()
            }
        }
    }

    private var settingsMemberAccessibilityLabel: String {
        if let user = member.user {
            return "\(decoratedMemberName(for: user)), @\(user.userName), \(rolePresentation.accessibilityText)"
        }
        return "\("Member".localized), \(rolePresentation.accessibilityText)"
    }
}

#Preview("Family settings — creator") {
    FamilySettings(familyId: "test")
        .environmentObject(FirebaseAuthService())
}

#Preview("Family settings — member") {
    FamilySettings(familyId: "test")
        .environmentObject(FirebaseAuthService())
}
