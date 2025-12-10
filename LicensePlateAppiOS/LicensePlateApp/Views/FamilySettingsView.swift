//
//  FamilySettingsView.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import SwiftUI
import SwiftData

struct FamilySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authService: FirebaseAuthService
    @Bindable var family: Family
    
    @State private var familyName: String = ""
    @State private var showRemoveMemberConfirmation: FamilyMember?
    @State private var showLeaveFamilyConfirmation = false
    
    var currentUser: AppUser? {
        authService.currentUser
    }
    
    var isCaptain: Bool {
        guard let userID = currentUser?.id else { return false }
        return family.members.contains { $0.userID == userID && $0.role == .captain && $0.isActive }
    }
    
    var body: some View {
        NavigationStack {
            AppBackgroundView {
                List {
                    // Family Name Section
                    if isCaptain {
                        Section("Family Name".localized) {
                            TextField("Family Name".localized, text: $familyName)
                                .onAppear {
                                    familyName = family.name ?? ""
                                }
                            Button {
                                family.name = familyName.isEmpty ? nil : familyName
                                family.lastUpdated = .now
                            } label: {
                                Text("Save Name".localized)
                            }
                            .disabled(familyName == (family.name ?? ""))
                        }
                        .textCase(nil)
                    }
                    
                    // Family Limits Section
                    Section("Family Limits".localized) {
                        HStack {
                            Text("Captains".localized)
                            Spacer()
                            Text("\(family.captains.count) / \(family.maxCaptains)")
                                .foregroundStyle(.secondary)
                        }
                        
                        HStack {
                            Text("Scouts".localized)
                            Spacer()
                            Text("\(family.scouts.count) / \(family.maxScouts)")
                                .foregroundStyle(.secondary)
                        }
                        
                        if family.isAtLimit(for: .captain) || family.isAtLimit(for: .scout) {
                            Text("Family is at or over recommended limits".localized)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .textCase(nil)
                    
                    // Members Section
                    Section("Family Members".localized) {
                        ForEach(family.members.filter { $0.isActive }) { member in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("User \(member.userID.prefix(8))")
                                        .font(.headline)
                                    Text(member.role.displayName)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                if isCaptain && member.userID != currentUser?.id {
                                    Button(role: .destructive) {
                                        showRemoveMemberConfirmation = member
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundStyle(.red)
                                    }
                                }
                            }
                        }
                    }
                    .textCase(nil)
                    
                    // Linked Families (for Retired Generals)
                    if !family.linkedFamilyIDs.isEmpty {
                        Section("Linked Families".localized) {
                            Text("\(family.linkedFamilyIDs.count) linked family(ies)".localized)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .textCase(nil)
                    }
                    
                    // Leave Family Section
                    Section {
                        Button(role: .destructive) {
                            showLeaveFamilyConfirmation = true
                        } label: {
                            Text("Leave Family".localized)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
                .navigationTitle("Family Settings".localized)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            dismiss()
                        } label: {
                            Text("Done".localized)
                        }
                    }
                }
                .alert("Remove Member".localized, isPresented: .constant(showRemoveMemberConfirmation != nil)) {
                    Button("Cancel".localized, role: .cancel) {
                        showRemoveMemberConfirmation = nil
                    }
                    Button("Remove".localized, role: .destructive) {
                        if let member = showRemoveMemberConfirmation {
                            removeMember(member)
                        }
                    }
                } message: {
                    Text("Are you sure you want to remove this member from the family?".localized)
                }
                .alert("Leave Family".localized, isPresented: $showLeaveFamilyConfirmation) {
                    Button("Cancel".localized, role: .cancel) { }
                    Button("Leave".localized, role: .destructive) {
                        leaveFamily()
                    }
                } message: {
                    Text("Are you sure you want to leave this family?".localized)
                }
            }
        }
    }
    
    private func removeMember(_ member: FamilyMember) {
        member.isActive = false
        family.lastUpdated = .now
        
        // Update user's familyID if they were removed
        let memberUserID = member.userID
        if let user = try? modelContext.fetch(FetchDescriptor<AppUser>(predicate: #Predicate<AppUser> {
            $0.id == memberUserID
        })).first {
            user.familyID = nil
        }
        
        showRemoveMemberConfirmation = nil
    }
    
    private func leaveFamily() {
        guard let userID = currentUser?.id else { return }
        
        if let member = family.members.first(where: { $0.userID == userID }) {
            member.isActive = false
        }
        
        currentUser?.familyID = nil
        family.lastUpdated = .now
        
        dismiss()
    }
}

