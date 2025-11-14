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
    @State private var isCheckingUsername = false
    @FocusState private var isTextFieldFocused: Bool
    
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
                        // User Name Card
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Username")
                                .font(.system(.headline, design: .rounded))
                                .foregroundStyle(Color.Theme.primaryBlue)
                            
                            if isEditingUserName {
                                HStack(spacing: 12) {
                                    TextField("Enter username", text: $editingUserName)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(.body, design: .rounded))
                                        .focused($isTextFieldFocused)
                                    
                                    Button("Save") {
                                        saveUserName()
                                    }
                                    .font(.system(.body, design: .rounded))
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill(Color.Theme.primaryBlue)
                                    )
                                    .disabled(isCheckingUsername)
                                    
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
                                    
                                  //WTF Does this button work on
                                    Button {
                                        editingUserName = currentUserName
                                        isEditingUserName = true
                                        // Set focus after a small delay to ensure the text field is visible
                                        Task { @MainActor in
                                            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                                            isTextFieldFocused = true
                                        }
                                    } label: {
                                        Image(systemName: "pencil")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(Color.Theme.primaryBlue)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.Theme.cardBackground)
                        )
                      
                        // Email Card
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Email")
                                    .font(.system(.headline, design: .rounded))
                                    .foregroundStyle(Color.Theme.primaryBlue)
                                
                                Spacer()
                                
                                Toggle("", isOn: Binding(
                                    get: { user.isEmailPublic },
                                    set: { newValue in
                                        user.isEmailPublic = newValue
                                        try? modelContext.save()
                                    }
                                ))
                                .labelsHidden()
                            }
                            
                            Text((user.email != nil) ? "\(user.email!)" : "Not set")
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(Color.Theme.softBrown)
                            
                            Text(user.isEmailPublic ? "Public - Others can find you by email" : "Private - Only you can see this")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(Color.Theme.softBrown.opacity(0.7))
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.Theme.cardBackground)
                        )
                        
                        // Phone Card
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Phone")
                                    .font(.system(.headline, design: .rounded))
                                    .foregroundStyle(Color.Theme.primaryBlue)
                                
                                Spacer()
                                
                                Toggle("", isOn: Binding(
                                    get: { user.isPhonePublic },
                                    set: { newValue in
                                        user.isPhonePublic = newValue
                                        try? modelContext.save()
                                    }
                                ))
                                .labelsHidden()
                            }
                            
                            Text((user.phoneNumber != nil) ? "\(user.phoneNumber!)" : "Not set")
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(Color.Theme.softBrown)
                            
                            Text(user.isPhonePublic ? "Public - Others can find you by phone" : "Private - Only you can see this")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(Color.Theme.softBrown.opacity(0.7))
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.Theme.cardBackground)
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
        
        // Check username uniqueness
        isCheckingUsername = true
        Task {
            do {
                // Check if username is taken
                let isTaken = try await authService.isUsernameTaken(trimmedName)
                
                if isTaken {
                    errorMessage = "This username is already taken. Please choose another."
                    showError = true
                    isCheckingUsername = false
                    return
                }
                
                // Update in auth service (which also checks uniqueness)
                try await authService.updateUserName(trimmedName)
                
                // Update local state
                currentUserName = trimmedName
                
                // Save to SwiftData
                try modelContext.save()
                
                isEditingUserName = false
                isTextFieldFocused = false
                isCheckingUsername = false
            } catch {
                errorMessage = error.localizedDescription
                showError = true
                isCheckingUsername = false
            }
        }
    }
    
    private func cancelEditing() {
        editingUserName = ""
        isEditingUserName = false
        isTextFieldFocused = false
    }
}

