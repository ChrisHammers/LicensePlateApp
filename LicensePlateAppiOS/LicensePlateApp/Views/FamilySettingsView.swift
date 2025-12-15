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
    @State private var showDeleteFamilyConfirmation = false
    @State private var memberUserNames: [String: String] = [:] // [userID: userName]
    
    var currentUser: AppUser? {
        authService.currentUser
    }
    
    var isCaptain: Bool {
        guard let userID = currentUser?.id else { return false }
        return family.members.contains { $0.userID == userID && $0.role == .captain && $0.isActive }
    }
    
    /// Check if current user is the original creator of the family
    var isOriginalCreator: Bool {
        guard let userID = currentUser?.id else { return false }
        // Find the first captain (original creator) by earliest joinedAt date
        let captains = family.members.filter { $0.role == .captain && $0.isActive }
        guard let firstCaptain = captains.min(by: { $0.joinedAt < $1.joinedAt }) else {
            return false
        }
        return firstCaptain.userID == userID
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
                                family.needsSync = true
                                
                                // Sync to Firebase
                                Task {
                                    do {
                                        try await FirebaseFamilySyncService.shared.saveFamilyToFirestore(family)
                                    } catch {
                                        print("Error syncing family name: \(error)")
                                    }
                                }
                            } label: {
                                Text("Save Name".localized)
                            }
                            .disabled(familyName == (family.name ?? ""))
                        }
                        .textCase(nil)
                    }
                    
                    // Share Code Section (only for captains)
                    if isCaptain {
                        Section("Share Code".localized) {
                            Toggle("Enable Share Code".localized, isOn: Binding(
                                get: { family.showShareCode },
                                set: { newValue in
                                    family.showShareCode = newValue
                                    family.lastUpdated = .now
                                    family.needsSync = true
                                    
                                    // Generate share code if enabling and one doesn't exist
                                    if newValue && family.shareCode == nil {
                                        family.generateShareCodeIfNeeded()
                                    }
                                    
                                    // Sync to Firebase
                                    Task {
                                        do {
                                            try await FirebaseFamilySyncService.shared.saveFamilyToFirestore(family)
                                        } catch {
                                            print("Error syncing share code setting: \(error)")
                                        }
                                    }
                                }
                            ))
                            
                            if family.showShareCode, let shareCode = family.shareCode {
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
                                    
                                    Button {
                                        family.regenerateShareCode()
                                        family.lastUpdated = .now
                                        family.needsSync = true
                                        
                                        // Sync to Firebase
                                        Task {
                                            do {
                                                try await FirebaseFamilySyncService.shared.saveFamilyToFirestore(family)
                                            } catch {
                                                print("Error syncing share code: \(error)")
                                            }
                                        }
                                    } label: {
                                        Image(systemName: "arrow.clockwise")
                                    }
                                }
                                
                                Text("Share this code with others to invite them to your family.".localized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
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
                                    Text(memberUserNames[member.userID] ?? "Unknown User".localized)
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
                    .task {
                        // Batch lookup all member userNames
                        let memberIDs = family.members.filter { $0.isActive }.map { $0.userID }
                        memberUserNames = await UserLookupHelper.getUserNames(for: memberIDs, in: modelContext)
                    }
                    
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
                            if isOriginalCreator {
                                showDeleteFamilyConfirmation = true
                            } else {
                                showLeaveFamilyConfirmation = true
                            }
                        } label: {
                            Text(isOriginalCreator ? "Delete Family".localized : "Leave Family".localized)
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
                .alert("Delete Family".localized, isPresented: $showDeleteFamilyConfirmation) {
                    Button("Cancel".localized, role: .cancel) { }
                    Button("Delete".localized, role: .destructive) {
                        deleteFamily()
                    }
                } message: {
                    Text("You are the original creator of this family. Deleting it will permanently remove the family and all its data. This action cannot be undone. Are you sure you want to delete this family?".localized)
                }
            }
        }
    }
    
    private func removeMember(_ member: FamilyMember) {
        member.isActive = false
        family.lastUpdated = .now
        family.needsSync = true
        
        // Update user's familyID if they were removed
        let memberUserID = member.userID
        if let user = try? modelContext.fetch(FetchDescriptor<AppUser>(predicate: #Predicate<AppUser> {
            $0.id == memberUserID
        })).first {
            user.familyID = nil
            user.needsSync = true
        }
        
        // Sync to Firebase
        Task {
            do {
                try await FirebaseFamilySyncService.shared.saveFamilyToFirestore(family)
                if let user = try? modelContext.fetch(FetchDescriptor<AppUser>(predicate: #Predicate<AppUser> {
                    $0.id == memberUserID
                })).first {
                    user.needsSync = true
                    try await authService.saveUserDataToFirestore(user)
                }
            } catch {
                print("Error syncing family member removal: \(error)")
            }
        }
        
        showRemoveMemberConfirmation = nil
    }
    
    private func leaveFamily() {
        guard let userID = currentUser?.id else { return }
        
        if let member = family.members.first(where: { $0.userID == userID }) {
            member.isActive = false
        }
        
        currentUser?.familyID = nil
        currentUser?.needsSync = true
        family.lastUpdated = .now
        family.needsSync = true
        
        // Sync to Firebase
        Task {
            do {
                try await FirebaseFamilySyncService.shared.saveFamilyToFirestore(family)
                if let user = currentUser {
                    user.needsSync = true
                    try await authService.saveUserDataToFirestore(user)
                }
            } catch {
                print("Error syncing family leave: \(error)")
            }
        }
        
        dismiss()
    }
    
    private func deleteFamily() {
        guard let userID = currentUser?.id,
              let firebaseFamilyID = family.firebaseFamilyID else { return }
        
        // Clear all members' familyID
        for member in family.members {
            let memberUserID = member.userID
            if let user = try? modelContext.fetch(FetchDescriptor<AppUser>(predicate: #Predicate<AppUser> {
                $0.id == memberUserID
            })).first {
                user.familyID = nil
                user.needsSync = true
            }
        }
        
        // Clear current user's familyID
        currentUser?.familyID = nil
        currentUser?.needsSync = true
        
        // Delete from Firestore
        Task {
            do {
                try await FirebaseFamilySyncService.shared.deleteFamilyFromFirestore(familyFirebaseID: firebaseFamilyID)
                
                // Delete from local data
                modelContext.delete(family)
                try? modelContext.save()
                
                // Sync user data
                if let user = currentUser {
                    user.needsSync = true
                    try await authService.saveUserDataToFirestore(user)
                }
                
                await MainActor.run {
                    dismiss()
                }
            } catch {
                print("Error deleting family: \(error)")
            }
        }
    }
}

