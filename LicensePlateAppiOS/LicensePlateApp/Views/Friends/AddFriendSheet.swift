//
//  AddFriendSheet.swift
//  LicensePlateApp
//
//  Created for Friends & Family MVP
//

import SwiftUI
import SwiftData

struct AddFriendSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authService: FirebaseAuthService
    @StateObject private var userRepository = UserRepository()
    @State private var searchQuery = ""
    @State private var searchType: UserRepository.SearchType = .all
    @State private var searchResults: [AppUser] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var showError = false
    
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
                            ForEach(searchResults) { user in
                                UserSearchResultRow(user: user)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Add Friend".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel".localized) {
                        dismiss()
                    }
                }
            }
            .onAppear {
                userRepository.setModelContext(modelContext)
                AnalyticsService.shared.log(.addFriendCTATapped)
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
            .alert("Error".localized, isPresented: $showError) {
                Button("OK".localized) {}
            } message: {
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                }
            }
            .onDisappear {
                searchTask?.cancel()
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
            let results = try await userRepository.searchUsers(query: searchQuery, searchType: searchType)
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

struct UserSearchResultRow: View {
    let user: AppUser
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
            
            Button("Add".localized) {
                // Send friend invite via Cloud Function
                AnalyticsService.shared.log(.userSearchResultSelected)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.Theme.primaryBlue)
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    AddFriendSheet()
        .environmentObject(FirebaseAuthService())
}

