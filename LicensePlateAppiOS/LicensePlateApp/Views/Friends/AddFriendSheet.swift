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
                }
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

