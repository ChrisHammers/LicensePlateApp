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
    
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isCheckingUsername = false
    
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
                        // Username - Editable
                        SettingEditableTextRow(
                            title: "Username",
                            value: $currentUserName,
                            placeholder: "Enter username",
                            detail: nil,
                            isDisabled: isCheckingUsername,
                            onSave: {
                                saveUserName()
                            },
                            onCancel: {
                                cancelEditing()
                            }
                        )
                      
                        // Email - Share Data Toggle
                        SettingShareDataToggleRow(
                            title: "Email",
                            value: Binding(
                                get: { user.email },
                                set: { newValue in
                                    user.email = newValue
                                }
                            ),
                            detail: nil,
                            isOn: Binding(
                                get: { user.isEmailPublic },
                                set: { newValue in
                                    user.isEmailPublic = newValue
                                    try? modelContext.save()
                                }
                            ),
                            isEditable: false,
                            onSave: {
                                try? modelContext.save()
                            },
                            onCancel: {
                                // Reset to original value if needed
                            }
                        )
                        
                        // Phone - Share Data Toggle
                        SettingShareDataToggleRow(
                            title: "Phone",
                            value: Binding(
                                get: { user.phoneNumber },
                                set: { newValue in
                                    user.phoneNumber = newValue
                                }
                            ),
                            detail: nil,
                            isOn: Binding(
                                get: { user.isPhonePublic },
                                set: { newValue in
                                    user.isPhonePublic = newValue
                                    try? modelContext.save()
                                }
                            ),
                            isEditable: false,
                            onSave: {
                                try? modelContext.save()
                            },
                            onCancel: {
                                // Reset to original value if needed
                            }
                        )
                        
                    } header: {
                        Text("Account Information")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(Color.Theme.primaryBlue)
                    }
                    .textCase(nil)
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init(top: 8, leading: 20, bottom: 8, trailing: 20))
                    
                    // Linked Accounts Section
                    Section {
                        VStack(alignment: .leading, spacing: 16) {
                            if user.linkedPlatforms.isEmpty {
                                Text("No accounts linked")
                                    .font(.system(.body, design: .rounded))
                                    .foregroundStyle(Color.Theme.softBrown)
                            } else {
                                ForEach(user.linkedPlatforms, id: \.platform) { platform in
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text(platform.platform.rawValue)
                                                .font(.system(.body, design: .rounded))
                                                .fontWeight(.semibold)
                                                .foregroundStyle(Color.Theme.primaryBlue)
                                            
                                            Spacer()
                                            
                                            Text("Linked")
                                                .font(.system(.caption, design: .rounded))
                                                .foregroundStyle(Color.Theme.softBrown)
                                        }
                                        
                                        if let email = platform.email {
                                            Text("Email: \(email)")
                                                .font(.system(.caption, design: .rounded))
                                                .foregroundStyle(Color.Theme.softBrown.opacity(0.8))
                                        }
                                        
                                        if let phone = platform.phoneNumber {
                                            Text("Phone: \(phone)")
                                                .font(.system(.caption, design: .rounded))
                                                .foregroundStyle(Color.Theme.softBrown.opacity(0.8))
                                        }
                                        
                                        if let displayName = platform.displayName {
                                            Text("Name: \(displayName)")
                                                .font(.system(.caption, design: .rounded))
                                                .foregroundStyle(Color.Theme.softBrown.opacity(0.8))
                                        }
                                    }
                                    .padding(.vertical, 8)
                                }
                            }
                            
                            // Placeholder for future platform linking buttons
                            Text("Platform linking coming soon")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(Color.Theme.softBrown.opacity(0.7))
                                .italic()
                                .padding(.top, 4)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.Theme.cardBackground)
                        )
                    } header: {
                        Text("Linked Accounts")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(Color.Theme.primaryBlue)
                    }
                    .textCase(nil)
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init(top: 8, leading: 20, bottom: 8, trailing: 20))
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
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
        let trimmedName = currentUserName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedName.isEmpty else {
            errorMessage = "Username cannot be empty"
            showError = true
            currentUserName = user.userName // Reset to original
            return
        }
        
        guard trimmedName != user.userName else {
            return // No change needed
        }
        
        // Check username uniqueness
        isCheckingUsername = true
        Task {
            do {
                // Check if username is taken
                let isTaken = try await authService.isUsernameTaken(trimmedName)
                
                if isTaken {
                    errorMessage = "This username is already taken. Please choose another."
                    showError = true
                    currentUserName = user.userName // Reset to original
                    isCheckingUsername = false
                    return
                }
                
                // Update in auth service (which also checks uniqueness)
                try await authService.updateUserName(trimmedName)
                
                // Save to SwiftData
                try modelContext.save()
                
                isCheckingUsername = false
            } catch {
                errorMessage = error.localizedDescription
                showError = true
                currentUserName = user.userName // Reset to original
                isCheckingUsername = false
            }
        }
    }
    
    private func cancelEditing() {
        currentUserName = user.userName // Reset to original
    }
}

