//
//  CreateFamilySheet.swift
//  LicensePlateApp
//
//  Created for Friends & Family MVP
//

import SwiftUI
import SwiftData

struct CreateFamilySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authService: FirebaseAuthService
    private let familyRepository = FamilyRepository.shared
    @State private var familyName = ""
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var showError = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.Theme.background
                    .ignoresSafeArea()
                
                Form {
                    Section {
                        TextField("Family Name".localized, text: $familyName)
                            .textInputAutocapitalization(.words)
                            .disabled(isCreating)
                    } header: {
                        Text("Family Name".localized)
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(Color.Theme.primaryBlue)
                    } footer: {
                        Text("Choose a name for your family group".localized)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                    }
                    
                    if let error = errorMessage {
                        Section {
                            Text(error)
                                .foregroundStyle(.red)
                                .font(.system(.caption, design: .rounded))
                        }
                    }
                }
                .formStyle(.grouped)
                .disabled(isCreating)
                
                // Loading overlay
                if isCreating {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(Color.Theme.primaryBlue)
                        
                        Text("Creating family...".localized)
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(Color.Theme.primaryBlue)
                    }
                    .padding(24)
                    .background(Color.Theme.background)
                    .cornerRadius(12)
                    .shadow(radius: 10)
                }
            }
            .navigationTitle("Create Family".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel".localized) {
                        dismiss()
                    }
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.Theme.primaryBlue)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create".localized) {
                        createFamily()
                    }
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .disabled(familyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating || !authService.isOnline)
                }
            }
            .alert("Error".localized, isPresented: $showError) {
                Button("OK".localized, role: .cancel) { }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
            }
            .onAppear {
                familyRepository.setModelContext(modelContext)
                AnalyticsService.shared.log(.familyCreateCTATapped)
            }
        }
    }
    
    private func createFamily() {
        let trimmedName = familyName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        guard authService.isOnline else {
            errorMessage = "Requires network connection".localized
            showError = true
            return
        }
        
        isCreating = true
        errorMessage = nil
        
        Task {
            do {
                // Create family via Cloud Function
                let familyId = try await familyRepository.createFamily(name: trimmedName)
                
                // Refresh user data from Firestore to get updated activeFamilyId
                try await authService.refreshCurrentUserFromFirestore()
                
                await MainActor.run {
                    isCreating = false
                    AnalyticsService.shared.log(.familyCreated)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isCreating = false
                    errorMessage = error.localizedDescription
                    showError = true
                    AnalyticsService.shared.log(.familyCreateFailed(error: error.localizedDescription))
                }
            }
        }
    }
}

#Preview {
    CreateFamilySheet()
        .environmentObject(FirebaseAuthService())
}

