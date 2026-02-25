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
    @State private var isLeavingFamily = false
    @State private var leaveFamilyError: String?
    @State private var showErrorAlert = false
    @State private var showDeleteFamilyConfirmation = false
    @State private var isDeletingFamily = false
    
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
            ZStack {
                Color.Theme.background
                    .ignoresSafeArea()
                
                List {
                    // Family Name
                    if viewModel.isCaptainOrCreator {
                        Section("Family Name".localized) {
                            SettingEditableTextRow(
                                title: "Name".localized,
                                value: $viewModel.familyName,
                                placeholder: "Enter family name".localized,
                                onSave: {
                                    // Update via Cloud Function
                                },
                                onCancel: {}
                            )
                        }
                    }
                    
                    // Members
                    Section("Members".localized) {
                        ForEach(viewModel.members) { member in
                            FamilyMemberSettingsRow(member: member)
                        }
                    }
                    
                    // Leave Family (All members except creator)
                    if !viewModel.isCreator {
                        Section {
                            Button(role: .destructive) {
                                showLeaveFamilyConfirmation = true
                            } label: {
                                Text("Leave Family".localized)
                                    .foregroundColor(.red)
                            }
                        } header: {
                            Text("Leave Family".localized)
                        } footer: {
                            Text("You will be removed from this family and will need to be invited again to rejoin.".localized)
                        }
                    }
                    
                    // Danger Zone (Creator only)
                    if viewModel.isCreator {
                        Section {
                            Button(role: .destructive) {
                                showDeleteFamilyConfirmation = true
                            } label: {
                                if isDeletingFamily {
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
                            .disabled(isDeletingFamily)
                        } header: {
                            Text("Danger Zone".localized)
                        } footer: {
                            Text("This will permanently delete the family and remove all members. This action cannot be undone.".localized)
                        }
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
            .alert("Leave Family".localized, isPresented: $showLeaveFamilyConfirmation) {
                Button("Cancel".localized, role: .cancel) {}
                Button("Leave".localized, role: .destructive) {
                    leaveFamily()
                }
            } message: {
                Text("Are you sure you want to leave this family? You will need to be invited again to rejoin.".localized)
            }
            .alert("Error".localized, isPresented: $showErrorAlert) {
                Button("OK".localized) {
                    leaveFamilyError = nil
                }
            } message: {
                if let error = leaveFamilyError {
                    Text(error)
                }
            }
            .alert("Delete Family".localized, isPresented: $showDeleteFamilyConfirmation) {
                Button("Cancel".localized, role: .cancel) {}
                Button("Delete".localized, role: .destructive) {
                    deleteFamily()
                }
            } message: {
                Text("Are you sure you want to delete this family? This will permanently remove the family and all its members. This action cannot be undone.".localized)
            }
        }
    }
    
    private func leaveFamily() {
        guard authService.isOnline else {
            leaveFamilyError = "Requires network connection".localized
            showErrorAlert = true
            return
        }
        
        isLeavingFamily = true
        leaveFamilyError = nil
        
        Task {
            do {
                try await FamilyRepository.shared.leaveFamily(familyId: familyId)
                
                await MainActor.run {
                    isLeavingFamily = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isLeavingFamily = false
                    leaveFamilyError = error.localizedDescription
                    showErrorAlert = true
                }
            }
        }
    }
    
    private func deleteFamily() {
        guard authService.isOnline else {
            leaveFamilyError = "Requires network connection".localized
            showErrorAlert = true
            return
        }
        
        // Prevent multiple calls
        guard !isDeletingFamily else { return }
        
        isDeletingFamily = true
        leaveFamilyError = nil
        
        Task {
            do {
                try await FamilyRepository.shared.deleteFamily(familyId: familyId)
                
                // Refresh current user from Firestore to get updated activeFamilyId
                try? await authService.refreshCurrentUserFromFirestore()
                
                await MainActor.run {
                    isDeletingFamily = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isDeletingFamily = false
                    leaveFamilyError = error.localizedDescription
                    showErrorAlert = true
                }
            }
        }
    }
}

struct FamilyMemberSettingsRow: View {
    let member: FamilyMember
    
    var body: some View {
        HStack {
            Circle()
                .fill(Color.Theme.primaryBlue.opacity(0.3))
                .frame(width: 40, height: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(member.user?.displayName ?? "Member")
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
    }
}

#Preview {
    FamilySettings(familyId: "test")
        .environmentObject(FirebaseAuthService())
}

