//
//  UserProfileView.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import SwiftUI
import SwiftData

struct UserProfileView: View {
    @Bindable var user: AppUser
    @ObservedObject var authService: FirebaseAuthService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    // Keep a local copy for editing
    @State private var currentUserName: String
    
    @State private var editingUserName: String = ""
    @State private var isEditingUserName = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    init(user: AppUser, authService: FirebaseAuthService) {
        self.user = user
        self.authService = authService
        _currentUserName = State(initialValue: user.userName)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.Theme.background
                    .ignoresSafeArea()
                
                List {
                    Section {
                        // User Name
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Username")
                                .font(.system(.headline, design: .rounded))
                                .foregroundStyle(Color.Theme.primaryBlue)
                            
                            if isEditingUserName {
                                HStack {
                                    TextField("Enter username", text: $editingUserName)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(.body, design: .rounded))
                                    
                                    Button("Save") {
                                        saveUserName()
                                    }
                                    .font(.system(.body, design: .rounded))
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.Theme.primaryBlue)
                                    
                                    Button("Cancel") {
                                        cancelEditing()
                                    }
                                    .font(.system(.body, design: .rounded))
                                    .foregroundStyle(Color.Theme.softBrown)
                                }
                            } else {
                                HStack {
                                    Text(currentUserName)
                                        .font(.system(.body, design: .rounded))
                                        .foregroundStyle(Color.Theme.primaryBlue)
                                    
                                    Spacer()
                                    
                                    Button {
                                        editingUserName = currentUserName
                                        isEditingUserName = true
                                    } label: {
                                        Image(systemName: "pencil")
                                            .foregroundStyle(Color.Theme.primaryBlue)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 8)
                        
                        // Email (if available)
                        if let email = user.email {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Email")
                                    .font(.system(.headline, design: .rounded))
                                    .foregroundStyle(Color.Theme.primaryBlue)
                                
                                Text(email)
                                    .font(.system(.body, design: .rounded))
                                    .foregroundStyle(Color.Theme.softBrown)
                            }
                            .padding(.vertical, 8)
                        }
                    } header: {
                        Text("Account Information")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(Color.Theme.primaryBlue)
                    }
                    .textCase(nil)
                    .listRowBackground(Color.clear)
                    
                    // Platform Linking Section (for future implementation)
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Linked Platforms")
                                .font(.system(.headline, design: .rounded))
                                .foregroundStyle(Color.Theme.primaryBlue)
                            
                            if user.linkedPlatforms.isEmpty {
                                Text("No platforms linked")
                                    .font(.system(.body, design: .rounded))
                                    .foregroundStyle(Color.Theme.softBrown)
                            } else {
                                ForEach(user.linkedPlatforms, id: \.platform) { platform in
                                    HStack {
                                        Text(platform.platform.rawValue)
                                            .font(.system(.body, design: .rounded))
                                            .foregroundStyle(Color.Theme.primaryBlue)
                                        
                                        Spacer()
                                        
                                        Text("Linked")
                                            .font(.system(.caption, design: .rounded))
                                            .foregroundStyle(Color.Theme.softBrown)
                                    }
                                }
                            }
                            
                            // Placeholder for future platform linking buttons
                            Text("Platform linking coming soon")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(Color.Theme.softBrown.opacity(0.7))
                                .italic()
                                .padding(.top, 4)
                        }
                        .padding(.vertical, 8)
                    } header: {
                        Text("Social Accounts")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(Color.Theme.primaryBlue)
                    }
                    .textCase(nil)
                    .listRowBackground(Color.clear)
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .onChange(of: user.userName) { oldValue, newValue in
                currentUserName = newValue
            }
        }
        .background(Color.Theme.background)
    }
    
    private func saveUserName() {
        let trimmedName = editingUserName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedName.isEmpty else {
            errorMessage = "Username cannot be empty"
            showError = true
            return
        }
        
        guard trimmedName != currentUserName else {
            isEditingUserName = false
            return
        }
        
        // Update local state
        currentUserName = trimmedName
        
        // Update user model
        user.updateUserName(trimmedName)
        
        // Update in auth service
        Task {
            do {
                try await authService.updateUserName(trimmedName)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
        
        // Save to SwiftData
        do {
            try modelContext.save()
        } catch {
            errorMessage = "Failed to save username: \(error.localizedDescription)"
            showError = true
        }
        
        isEditingUserName = false
    }
    
    private func cancelEditing() {
        editingUserName = ""
        isEditingUserName = false
    }
}

