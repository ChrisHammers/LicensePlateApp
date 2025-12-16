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
    
    init(familyId: String) {
        self.familyId = familyId
        let familyRepo = FamilyRepository()
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
                    
                    // Danger Zone (Creator only)
                    if viewModel.isCreator {
                        Section {
                            Button(role: .destructive) {
                                // Inactivate family
                            } label: {
                                Text("Delete Family".localized)
                                    .foregroundColor(.red)
                            }
                        } header: {
                            Text("Danger Zone".localized)
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
                viewModel.loadData(familyId: familyId)
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
            
            VStack(alignment: .leading) {
                Text(member.user?.displayName ?? "Member")
                    .font(.system(.body, design: .rounded))
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

#Preview {
    FamilySettings(familyId: "test")
        .environmentObject(FirebaseAuthService())
}

