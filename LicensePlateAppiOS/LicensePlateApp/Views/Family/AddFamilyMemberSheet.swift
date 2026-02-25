//
//  AddFamilyMemberSheet.swift
//  LicensePlateApp
//
//  Created for Friends & Family MVP
//

import SwiftUI
import SwiftData

struct AddFamilyMemberSheet: View {
    let familyId: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authService: FirebaseAuthService
    private let userRepository = UserRepository.shared
    private let familyRepository = FamilyRepository.shared
    @State private var searchQuery = ""
    @State private var searchType: UserRepository.SearchType = .all
    @State private var searchResults: [UserRepository.UserSearchResult] = []
    @State private var isSearching = false
    @State private var isInviting = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showSuccessAlert = false
    @State private var searchTask: Task<Void, Never>?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.Theme.background
                    .ignoresSafeArea()
                
                List {
                    Section("Search".localized) {
                        TextField("Username, email, or phone".localized, text: $searchQuery)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                Task {
                                    await performSearch()
                                }
                            }
                        
                        if searchQuery.count < 3 && !searchQuery.isEmpty {
                            Text("Enter at least 3 characters to search".localized)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(Color.Theme.softBrown)
                        }
                        
                        if isSearching {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Searching...".localized)
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(Color.Theme.softBrown)
                            }
                        }
                    }
                    
                    if !searchResults.isEmpty {
                        Section("Results".localized) {
                            ForEach(Array(searchResults.enumerated()), id: \.element.user.id) { index, result in
                                FamilyMemberSearchResultRow(
                                    result: result,
                                    familyId: familyId,
                                    familyRepository: familyRepository,
                                    isInviting: $isInviting,
                                    errorMessage: $errorMessage,
                                    showError: $showError,
                                    showSuccessAlert: $showSuccessAlert
                                )
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .disabled(isInviting)
                
                if isInviting {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                }
            }
            .navigationTitle("Invite Member".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel".localized) {
                        dismiss()
                    }
                    .disabled(isInviting)
                }
            }
            .onAppear {
                userRepository.setModelContext(modelContext)
                familyRepository.setModelContext(modelContext)
            }
            .onChange(of: searchQuery) { oldValue, newValue in
                // Cancel previous search task
                searchTask?.cancel()
                
                // Clear results if query is too short
                if newValue.count < 3 {
                    searchResults = []
                    isSearching = false
                    return
                }
                
                // Debounce search - wait 500ms after user stops typing
                searchTask = Task {
                    do {
                        try await Task.sleep(nanoseconds: 500_000_000) // 500ms
                        
                        // Check if task was cancelled
                        try Task.checkCancellation()
                        
                        // Perform search
                        await performSearch()
                    } catch {
                        // Task was cancelled or failed - ignore
                    }
                }
            }
            .onDisappear {
                searchTask?.cancel()
            }
            .alert("Error".localized, isPresented: $showError) {
                Button("OK".localized) {}
            } message: {
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                }
            }
            .alert("Invite Sent".localized, isPresented: $showSuccessAlert) {
                Button("OK".localized) {
                    dismiss()
                }
            } message: {
                Text("Family invitation has been sent successfully.".localized)
            }
        }
    }
    
    private func performSearch() async {
        // Minimum 3 characters required
        guard searchQuery.count >= 3 else {
            await MainActor.run {
                searchResults = []
                isSearching = false
            }
            return
        }
        
        await MainActor.run {
            isSearching = true
            errorMessage = nil
        }
        
        do {
            // Get current user ID to exclude from results
            let currentUserId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id
            let results = try await userRepository.searchUsers(query: searchQuery, searchType: searchType, excludeUserId: currentUserId)
            await MainActor.run {
                searchResults = results
                isSearching = false
                AnalyticsService.shared.log(.userSearchPerformed(queryType: searchType == .all ? "all" : searchType == .username ? "username" : searchType == .email ? "email" : "phone"))
                
                // Log if no results found for debugging
                if results.isEmpty {
                    print("🔍 Search for '\(searchQuery)' returned no results")
                }
            }
        } catch {
            await MainActor.run {
                isSearching = false
                errorMessage = error.localizedDescription
                showError = true
                print("❌ Search error: \(error.localizedDescription)")
            }
        }
    }
}

struct FamilyMemberSearchResultRow: View {
    let result: UserRepository.UserSearchResult
    let familyId: String
    let familyRepository: FamilyRepository
    @Binding var isInviting: Bool
    @Binding var errorMessage: String?
    @Binding var showError: Bool
    @Binding var showSuccessAlert: Bool
    @EnvironmentObject var authService: FirebaseAuthService
    
    var user: AppUser { result.user }
    
    var body: some View {
        HStack {
            Circle()
                .fill(Color.Theme.primaryBlue.opacity(0.3))
                .frame(width: 50, height: 50)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(user.displayName)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                
                Text("@\(user.userName)")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                
                Text("Found by \(result.matchedField.displayName)".localized)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown.opacity(0.7))
            }
            
            Spacer()
            
            Button("Invite".localized) {
                sendInvite()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.Theme.primaryBlue)
            .disabled(isInviting || !authService.isOnline)
        }
        .padding(.vertical, 8)
    }
    
    private func sendInvite() {
        guard authService.isOnline else {
            errorMessage = "Requires network connection".localized
            showError = true
            return
        }
        
        // Use firebaseUID if available, otherwise fall back to id
        let toUserId = user.firebaseUID ?? user.id
        
        print("📤 Sending family invite:")
        print("   - To User ID: \(toUserId)")
        print("   - Family ID: \(familyId)")
        print("   - Method: search")
        
        isInviting = true
        errorMessage = nil
        
        Task {
            do {
                let inviteId = try await familyRepository.sendFamilyInvite(
                    toUserId: toUserId,
                    familyId: familyId,
                    method: "search"
                )
                
                print("✅ Family invite sent successfully:")
                print("   - Invite ID: \(inviteId)")
                print("   - Check Firebase 'invites' collection for document ID: \(inviteId)")
                
                await MainActor.run {
                    isInviting = false
                    AnalyticsService.shared.log(.familyInviteSent)
                    showSuccessAlert = true
                }
            } catch {
                let nsError = error as NSError
                let errorCode = nsError.code
                let errorDomain = nsError.domain
                let errorDescription = error.localizedDescription
                
                print("❌ Family invite failed:")
                print("   - Error Domain: \(errorDomain)")
                print("   - Error Code: \(errorCode)")
                print("   - Error Description: \(errorDescription)")
                print("   - Full Error: \(error)")
                
                // Provide more user-friendly error messages
                let userFriendlyMessage: String
                if errorDescription.contains("permission-denied") {
                    userFriendlyMessage = "You don't have permission to invite members to this family.".localized
                } else if errorDescription.contains("failed-precondition") {
                    userFriendlyMessage = "Unable to invite this user. They may already be in a family or have reached the limit.".localized
                } else if errorDescription.contains("not-found") {
                    userFriendlyMessage = "User not found.".localized
                } else if errorDescription.contains("unauthenticated") {
                    userFriendlyMessage = "Please sign in to send invites.".localized
                } else {
                    userFriendlyMessage = "Failed to send invite: \(errorDescription)".localized
                }
                
                await MainActor.run {
                    isInviting = false
                    errorMessage = userFriendlyMessage
                    showError = true
                }
            }
        }
    }
}

#Preview {
    AddFamilyMemberSheet(familyId: "test")
        .environmentObject(FirebaseAuthService())
}

