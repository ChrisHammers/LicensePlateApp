//
//  UsernameConflictDialog.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import SwiftUI

struct UsernameConflictDialog: View {
    @ObservedObject var authService: FirebaseAuthService
    @State private var newUsername: String = ""
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    // Cancel on background tap
                    authService.resolveUsernameConflict(newUsername: nil)
                }
            
            VStack(spacing: 24) {
                Text("Username Conflict")
                    .font(.system(.title2, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                
                Text(authService.conflictDialogMessage)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                TextField("Enter new username", text: $newUsername)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .rounded))
                    .focused($isTextFieldFocused)
                    .padding(.horizontal)
                
                HStack(spacing: 16) {
                    Button("Cancel") {
                        authService.resolveUsernameConflict(newUsername: nil)
                    }
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.softBrown)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(Color.Theme.cardBackground)
                    )
                    
                    Button("Continue") {
                        let trimmed = newUsername.trimmingCharacters(in: .whitespacesAndNewlines)
                        authService.resolveUsernameConflict(newUsername: trimmed.isEmpty ? nil : trimmed)
                    }
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(Color.Theme.primaryBlue)
                    )
                    .disabled(newUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.Theme.background)
            )
            .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 10)
            .padding(.horizontal, 32)
        }
        .onAppear {
            newUsername = authService.conflictDialogNewUsername
            // Focus text field after a short delay
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                isTextFieldFocused = true
            }
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @StateObject private var authService = FirebaseAuthService()
        
        var body: some View {
            ZStack {
                Color.Theme.background
                    .ignoresSafeArea()
                
                Button("Show Dialog") {
                    authService.conflictDialogMessage = "Your username 'User123' is already taken. Please choose a new username to link your Google account."
                    authService.conflictDialogNewUsername = ""
                    authService.showUsernameConflictDialog = true
                }
                .padding()
                .background(Color.Theme.primaryBlue)
                .foregroundStyle(.white)
                .cornerRadius(12)
                
                if authService.showUsernameConflictDialog {
                    UsernameConflictDialog(authService: authService)
                }
            }
        }
    }
    
    return PreviewWrapper()
}

