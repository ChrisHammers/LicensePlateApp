//
//  InviteToFamilyView.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import SwiftUI
import SwiftData
import FirebaseFirestore
import FirebaseAuth

struct UserSearchResult: Identifiable, Hashable {
    let id: String // userID
    let userName: String
    let email: String? // Only set if isEmailPublic == true
    let phoneNumber: String? // Only set if isPhonePublic == true
    let matchedField: String // "username", "email", or "phone"
}

struct InviteToFamilyView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authService: FirebaseAuthService
    var family: Family?
    
    @State private var selectedRole: FamilyMember.FamilyRole = .sergeant
    @State private var invitationMethod: InvitationMethod = .shareCode
    @State private var enteredShareCode: String = "" // For joining with share code
    @State private var searchText: String = ""
    @State private var showRoleSelection = true
    
    // Search state
    @State private var searchResults: [UserSearchResult] = []
    @State private var selectedUserIDs: Set<String> = []
    @State private var isSearching: Bool = false
    @State private var searchError: String?
    @State private var searchTask: Task<Void, Never>?
    
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
    
    /// Check if current user is a captain of the family
    var isCaptain: Bool {
        guard let userID = currentUser?.id,
              let family = family else {
            // If creating new family, user will be captain
            return isCreatingNewFamily
        }
        return family.members.contains { member in
            member.userID == userID && 
            member.role == .captain && 
            member.isActive &&
            member.invitationStatus == .accepted
        }
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
                        if isCaptain {
                            Section("Invitation Method".localized) {
                                Picker("Method".localized, selection: $invitationMethod) {
                                    Text("Share Code".localized).tag(InvitationMethod.shareCode)
                                    Text("Search User".localized).tag(InvitationMethod.inAppSearch)
                                }
                                .pickerStyle(.segmented)
                            }
                            .textCase(nil)
                        } else {
                            // Show message if not captain
                            Section {
                                Text("Only captains can invite members to the family.".localized)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .textCase(nil)
                        }
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
                    
                    // Share Code Method (only show if captain has enabled it)
                    if invitationMethod == .shareCode {
                        Section {
                            if let family = family {
                                if family.showShareCode && isCaptain {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Family Share Code".localized)
                                            .font(.headline)
                                        
                                        if let familyShareCode = family.shareCode, !familyShareCode.isEmpty {
                                            HStack {
                                                Text(familyShareCode)
                                                    .font(.title2)
                                                    .fontWeight(.bold)
                                                    .fontDesign(.monospaced)
                                                
                                                Button {
                                                    UIPasteboard.general.string = familyShareCode
                                                } label: {
                                                    Image(systemName: "doc.on.doc")
                                                }
                                                
                                                Button {
                                                    regenerateShareCode()
                                                } label: {
                                                    Image(systemName: "arrow.clockwise")
                                                }
                                            }
                                            
                                            Text("Share this code with others to invite them to your family.".localized)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            
                                            Button {
                                                regenerateShareCode()
                                            } label: {
                                                HStack {
                                                    Image(systemName: "arrow.clockwise")
                                                    Text("Regenerate Code".localized)
                                                }
                                                .font(.subheadline)
                                            }
                                            .foregroundStyle(.blue)
                                        } else {
                                            Button {
                                                family.generateShareCodeIfNeeded()
                                                family.showShareCode = true
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
                                                Text("Generate Share Code".localized)
                                            }
                                        }
                                    }
                                } else if !isCaptain {
                                    Text("Only captains can view and manage the share code.".localized)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Share code is currently disabled. Enable it in family settings.".localized)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Enter Share Code".localized)
                                        .font(.headline)
                                    
                                    TextField("Enter code".localized, text: $enteredShareCode)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                    
                                    Button {
                                        joinFamilyWithCode()
                                    } label: {
                                        Text("Join Family".localized)
                                    }
                                    .disabled(enteredShareCode.isEmpty)
                                }
                            }
                        }
                        .textCase(nil)
                    }
                    
                    // In-App Search Method (only show if captain or creating new family)
                    if invitationMethod == .inAppSearch && (isCaptain || isCreatingNewFamily) {
                        Section {
                            TextField("Search by username, email, or phone".localized, text: $searchText)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .onChange(of: searchText) { oldValue, newValue in
                                    // Debounce search
                                    searchTask?.cancel()
                                    searchTask = Task {
                                        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
                                        if !Task.isCancelled {
                                            performSearch()
                                        }
                                    }
                                }
                            
                            // Search Results
                            if isSearching {
                                HStack {
                                    ProgressView()
                                    Text("Searching...".localized)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } else if let error = searchError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            } else if !searchResults.isEmpty {
                                ForEach(searchResults) { result in
                                    HStack {
                                        Button {
                                            if selectedUserIDs.contains(result.id) {
                                                selectedUserIDs.remove(result.id)
                                            } else {
                                                selectedUserIDs.insert(result.id)
                                            }
                                        } label: {
                                            Image(systemName: selectedUserIDs.contains(result.id) ? "checkmark.square.fill" : "square")
                                                .foregroundStyle(selectedUserIDs.contains(result.id) ? .blue : .secondary)
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(result.userName)
                                                .font(.headline)
                                            
                                            if let email = result.email {
                                                Text(email)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            
                                            if let phoneNumber = result.phoneNumber {
                                                Text(phoneNumber)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            
                                            Text("Matched: \(result.matchedField)".localized)
                                                .font(.caption2)
                                                .foregroundStyle(.blue)
                                        }
                                        
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if selectedUserIDs.contains(result.id) {
                                            selectedUserIDs.remove(result.id)
                                        } else {
                                            selectedUserIDs.insert(result.id)
                                        }
                                    }
                                }
                            } else if searchText.count >= 3 && !isSearching {
                                Text("No users found".localized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if searchText.count > 0 && searchText.count < 3 {
                                Text("Enter at least 3 characters to search".localized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            // Send Invites Button
                            if !selectedUserIDs.isEmpty {
                                Button {
                                    sendInvites()
                                } label: {
                                    HStack {
                                        Image(systemName: "paperplane.fill")
                                        Text("Send Invites (\(selectedUserIDs.count))".localized)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(!isCaptain)
                                .padding(.top, 8)
                            }
                        }
                        .textCase(nil)
                    }
                }
                .scrollContentBackground(.hidden)
                .navigationTitle(isCreatingNewFamily ? "Create or Join Family".localized : "Invite a Family Member".localized)
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
                .onAppear {
                    // Load share code from family if it exists
                    if let family = family, let code = family.shareCode {
                      enteredShareCode = code
                    }
                }
                .onChange(of: invitationMethod) { oldValue, newValue in
                    // Clear search when switching methods
                    if newValue != .inAppSearch {
                        searchText = ""
                        searchResults = []
                        selectedUserIDs.removeAll()
                        searchTask?.cancel()
                    }
                }
                .onDisappear {
                    // Cancel any pending searches
                    searchTask?.cancel()
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
        guard let family = family else { return }
        
        family.generateShareCodeIfNeeded()
      enteredShareCode = family.shareCode ?? ""
        family.lastUpdated = .now
        family.needsSync = true
        
        // Save and sync to Firebase
        do {
            try modelContext.save()
            
            Task {
                do {
                    try await FirebaseFamilySyncService.shared.saveFamilyToFirestore(family)
                } catch {
                    print("Error syncing family share code: \(error)")
                }
            }
        } catch {
            print("Error saving family share code: \(error)")
        }
    }
    
    private func regenerateShareCode() {
        guard let family = family else { return }
        
        family.regenerateShareCode()
      enteredShareCoded = family.shareCode ?? ""
        family.lastUpdated = .now
        family.needsSync = true
        
        // Save and sync to Firebase
        do {
            try modelContext.save()
            
            Task {
                do {
                    try await FirebaseFamilySyncService.shared.saveFamilyToFirestore(family)
                } catch {
                    print("Error syncing regenerated family share code: \(error)")
                }
            }
        } catch {
            print("Error saving regenerated family share code: \(error)")
        }
    }
    
    private func joinFamilyWithCode() {
        guard let userID = currentUser?.id,
              !enteredShareCode.isEmpty else {
            return
        }
        
        Task {
            do {
                // Search for family by share code
                guard let foundFamily = try await FirebaseFamilySyncService.shared.loadFamilyByShareCode(enteredShareCode) else {
                    // Show error - family not found
                    await MainActor.run {
                        // TODO: Show error alert
                        print("Family not found with share code: \(enteredShareCode)")
                    }
                    return
                }
                
                // Check if user is already a member
                if foundFamily.members.contains(where: { $0.userID == userID && $0.isActive }) {
                    await MainActor.run {
                        // TODO: Show error - already a member
                        print("User is already a member of this family")
                        dismiss()
                    }
                    return
                }
                
                // Add user as a member with selected role
                await MainActor.run {
                    let newMember = FamilyMember(
                        userID: userID,
                        familyID: foundFamily.id,
                        role: selectedRole,
                        joinedAt: .now,
                        invitedBy: nil,
                        isActive: true,
                        invitationStatus: .accepted, // Joining via share code is automatically accepted
                        invitedAt: nil
                    )
                    
                    foundFamily.members.append(newMember)
                    foundFamily.lastUpdated = .now
                    foundFamily.needsSync = true
                    
                    // Update user's familyID
                    currentUser?.familyID = foundFamily.id
                    currentUser?.needsSync = true
                    
                    // Save to model context
                    modelContext.insert(newMember)
                    
                    do {
                        try modelContext.save()
                        
                        // Sync to Firebase
                        Task {
                            do {
                                try await FirebaseFamilySyncService.shared.saveFamilyToFirestore(foundFamily)
                                try await FirebaseFamilySyncService.shared.saveFamilyMemberToFirestore(newMember, familyFirebaseID: foundFamily.firebaseFamilyID ?? "")
                                if let user = currentUser {
                                    user.needsSync = true
                                    try await authService.saveUserDataToFirestore(user)
                                }
                            } catch {
                                print("Error syncing family join: \(error)")
                            }
                        }
                        
                        dismiss()
                    } catch {
                        print("Error joining family: \(error)")
                    }
                }
            } catch {
                await MainActor.run {
                    // TODO: Show error alert
                    print("Error loading family by share code: \(error)")
                }
            }
        }
    }
    
    private func performSearch() {
        // Cancel previous search task
        searchTask?.cancel()
        
        // Clear results if query is too short
        guard searchText.count >= 3 else {
            searchResults = []
            searchError = nil
            return
        }
        
        isSearching = true
        searchError = nil
        
        searchTask = Task {
            do {
                let results = try await FirebaseFamilySyncService.shared.searchUsers(query: searchText)
                
                // Filter out current user and existing members (local check)
                var filteredResults = results.filter { result in
                    result.id != currentUser?.id && !isUserAlreadyMember(result.id)
                }
                
                // Also check Firestore for pending invitations if we have a family
                if let family = family, let firebaseFamilyID = family.firebaseFamilyID {
                    var resultsToRemove: [String] = []
                    await withTaskGroup(of: (String, Bool).self) { group in
                        for result in filteredResults {
                            group.addTask {
                                let hasPending = await self.hasPendingInvitationInFirestore(
                                    userID: result.id,
                                    familyFirebaseID: firebaseFamilyID
                                )
                                return (result.id, hasPending)
                            }
                        }
                        
                        for await (userID, hasPending) in group {
                            if hasPending {
                                resultsToRemove.append(userID)
                            }
                        }
                    }
                    
                    // Remove users with pending invitations
                    filteredResults.removeAll { resultsToRemove.contains($0.id) }
                }
                
                await MainActor.run {
                    if !Task.isCancelled {
                        searchResults = filteredResults
                        isSearching = false
                    }
                }
            } catch {
                await MainActor.run {
                    if !Task.isCancelled {
                        searchError = "Failed to search users: \(error.localizedDescription)"
                        searchResults = []
                        isSearching = false
                    }
                }
            }
        }
    }
    
    private func isUserAlreadyMember(_ userID: String) -> Bool {
        guard let family = family else { return false }
        // Check if user is an active member
        if family.members.contains(where: { $0.userID == userID && $0.isActive }) {
            return true
        }
        // Check if user has a pending invitation
        if family.members.contains(where: { $0.userID == userID && $0.invitationStatus == .pending }) {
            return true
        }
        return false
    }
    
    /// Check if user has pending invitation in Firestore (async)
    private func hasPendingInvitationInFirestore(userID: String, familyFirebaseID: String) async -> Bool {
        do {
            let db = Firestore.firestore()
            let memberRef = db.collection("families")
                .document(familyFirebaseID)
                .collection("members")
                .document(userID)
            
            let document = try await memberRef.getDocument()
            if document.exists,
               let data = document.data(),
               let statusString = data["invitationStatus"] as? String,
               statusString == "pending" {
                return true
            }
        } catch {
            print("Error checking Firestore for pending invitation: \(error)")
        }
        return false
    }
    
    private func sendInvites() {
        guard let family = family,
              let currentUserID = currentUser?.id,
              !selectedUserIDs.isEmpty else {
            return
        }
        
        // Only captains can send invites
        guard isCaptain else {
            searchError = "Only captains can invite members to the family.".localized
            return
        }
        
        // Check family limits
        let roleCount = family.membersWithRole(selectedRole).count
        let maxAllowed: Int
        switch selectedRole {
        case .captain:
            maxAllowed = family.maxCaptains
        case .scout:
            maxAllowed = family.maxScouts
        case .sergeant, .retiredGeneral:
            maxAllowed = Int.max // No limits
        }
        
        if roleCount + selectedUserIDs.count > maxAllowed {
            searchError = "Cannot add \(selectedUserIDs.count) \(selectedRole.displayName.lowercased())(s). Family limit is \(maxAllowed)."
            return
        }
        
        var newMembers: [FamilyMember] = []
        
        for userID in selectedUserIDs {
            // Double-check user is not already a member
            if isUserAlreadyMember(userID) {
                continue
            }
            
            // Cache userName from search results if available
            if let searchResult = searchResults.first(where: { $0.id == userID }) {
                UserLookupHelper.cacheUserInSwiftData(userID: userID, userName: searchResult.userName, modelContext: modelContext)
            }
            
            let newMember = FamilyMember(
                userID: userID,
                familyID: family.id,
                role: selectedRole,
                joinedAt: .now,
                invitedBy: currentUserID,
                isActive: false, // Not active until accepted
                invitationStatus: .pending,
                invitedAt: .now
            )
            
            family.members.append(newMember)
            newMembers.append(newMember)
            modelContext.insert(newMember)
        }
        
        family.lastUpdated = .now
        family.needsSync = true
        
        do {
            // Save context to ensure cached userNames are persisted
            try modelContext.save()
            
            // Also fetch any missing userNames from Firestore in background
            Task {
                for userID in selectedUserIDs {
                    // Only fetch if we didn't cache from search results
                    if searchResults.first(where: { $0.id == userID }) == nil {
                        _ = await UserLookupHelper.getUserName(for: userID, in: modelContext)
                    }
                }
            }
            
            // Sync to Firebase
            Task {
                do {
                    try await FirebaseFamilySyncService.shared.saveFamilyToFirestore(family)
                    for member in newMembers {
                        if let firebaseID = family.firebaseFamilyID {
                            try await FirebaseFamilySyncService.shared.saveFamilyMemberToFirestore(member, familyFirebaseID: firebaseID)
                            
                            // Send email notification (stub for now)
                            if let searchResult = searchResults.first(where: { $0.id == member.userID }) {
                                await FamilyNotificationService.shared.sendFamilyInvitationEmail(
                                    to: member.userID,
                                    email: searchResult.email,
                                    familyName: family.name,
                                    inviterName: currentUser?.userName ?? "Someone",
                                    role: member.role
                                )
                            }
                        }
                    }
                } catch {
                    print("Error syncing family invites: \(error)")
                }
            }
            
            // Clear selections and search
            selectedUserIDs.removeAll()
            searchResults = []
            searchText = ""
            dismiss()
        } catch {
            searchError = "Failed to send invites: \(error.localizedDescription)"
        }
    }
    
    private func createNewFamily() {
        guard let userID = currentUser?.id else {
            dismiss()
            return
        }
        
        // DEBUG: Print user ID values
        let firebaseAuthUID = FirebaseAuth.Auth.auth().currentUser?.uid
        let idsMatch = firebaseAuthUID != nil && userID == firebaseAuthUID
        print("🔍 DEBUG - Creating family:")
        print("   AppUser.id: \(userID)")
        print("   AppUser.firebaseUID: \(currentUser?.firebaseUID ?? "nil")")
        print("   Firebase Auth UID: \(firebaseAuthUID ?? "nil")")
        print("   Match: \(idsMatch)")
        
        // Create new family
        let newFamily = Family(
            name: nil, // Can be set later
            createdAt: .now,
            lastUpdated: .now
        )
        
        // Generate share code for the new family
        newFamily.generateShareCodeIfNeeded()
        
        // Add current user as Captain
        let captainMember = FamilyMember(
            userID: userID,
            familyID: newFamily.id,
            role: .captain,
            joinedAt: .now,
            invitedBy: nil,
            isActive: true,
            invitationStatus: .accepted, // Creator is automatically accepted
            invitedAt: nil
        )
        
        newFamily.members.append(captainMember)
        
        // Update user's familyID
        currentUser?.familyID = newFamily.id
        currentUser?.needsSync = true
        
        // Mark family for sync
        newFamily.needsSync = true
        
        // Save to model context
        modelContext.insert(newFamily)
        modelContext.insert(captainMember)
        
        do {
            try modelContext.save()
            
            // Sync to Firebase if online
            Task {
                do {
                    try await FirebaseFamilySyncService.shared.saveFamilyToFirestore(newFamily)
                    try await FirebaseFamilySyncService.shared.saveFamilyMemberToFirestore(captainMember, familyFirebaseID: newFamily.firebaseFamilyID ?? "")
                    if let user = currentUser {
                        user.needsSync = true
                        try await authService.saveUserDataToFirestore(user)
                    }
                } catch {
                    print("Error syncing family to Firebase: \(error)")
                }
            }
            
            dismiss()
        } catch {
            print("Error creating family: \(error)")
            dismiss()
        }
    }
}

