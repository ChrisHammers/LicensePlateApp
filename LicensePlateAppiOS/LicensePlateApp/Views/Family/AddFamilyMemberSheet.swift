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
    @StateObject private var userRepository = UserRepository()
    @StateObject private var familyRepository = FamilyRepository()
    @State private var searchQuery = ""
    @State private var searchType: UserRepository.SearchType = .all
    @State private var searchResults: [AppUser] = []
    @State private var isSearching = false
    @State private var isInviting = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showSuccessAlert = false
    
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
                                performSearch()
                            }
                        
                        Button("Search".localized) {
                            performSearch()
                        }
                        .disabled(searchQuery.isEmpty || isSearching)
                    }
                    
                    if !searchResults.isEmpty {
                        Section("Results".localized) {
                            ForEach(searchResults) { user in
                                FamilyMemberSearchResultRow(
                                    user: user,
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
    
    private func performSearch() {
        guard !searchQuery.isEmpty else { return }
        
        isSearching = true
        Task {
            do {
                let results = try await userRepository.searchUsers(query: searchQuery, searchType: searchType)
                await MainActor.run {
                    searchResults = results
                    isSearching = false
                    AnalyticsService.shared.log(.userSearchPerformed(queryType: searchType == .all ? "all" : searchType == .username ? "username" : searchType == .email ? "email" : "phone"))
                }
            } catch {
                await MainActor.run {
                    isSearching = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}

struct FamilyMemberSearchResultRow: View {
    let user: AppUser
    let familyId: String
    let familyRepository: FamilyRepository
    @Binding var isInviting: Bool
    @Binding var errorMessage: String?
    @Binding var showError: Bool
    @Binding var showSuccessAlert: Bool
    @EnvironmentObject var authService: FirebaseAuthService
    
    var body: some View {
        HStack {
            Circle()
                .fill(Color.Theme.primaryBlue.opacity(0.3))
                .frame(width: 50, height: 50)
            
            VStack(alignment: .leading) {
                Text(user.displayName)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                
                Text("@\(user.userName)")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
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
        
        isInviting = true
        errorMessage = nil
        
        Task {
            do {
                _ = try await familyRepository.sendFamilyInvite(
                    toUserId: toUserId,
                    familyId: familyId,
                    method: "search"
                )
                
                await MainActor.run {
                    isInviting = false
                    AnalyticsService.shared.log(.familyInviteSent)
                    showSuccessAlert = true
                }
            } catch {
                await MainActor.run {
                    isInviting = false
                    errorMessage = error.localizedDescription
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

