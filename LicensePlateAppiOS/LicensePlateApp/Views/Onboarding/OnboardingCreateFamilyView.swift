//
//  OnboardingCreateFamilyView.swift
//  LicensePlateApp
//
//  Created for Onboarding flow
//

import SwiftUI
import SwiftData

struct OnboardingCreateFamilyView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authService: FirebaseAuthService
    @ObservedObject var coordinator: OnboardingCoordinator
    let onNext: () -> Void
    
    private let familyRepository = FamilyRepository.shared
    
    @State private var familyName = ""
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var showError = false
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    Text("Create a Family".localized)
                        .font(.system(.largeTitle, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                    
                    Text("As a Captain, you can create a family group to add Scouts and track trips together.".localized)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Family Name".localized)
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(Color.Theme.primaryBlue)
                        
                        TextField("Enter family name".localized, text: $familyName)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.words)
                            .disabled(isCreating)
                    }
                    .padding()
                    .background(Color.Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)
                    
                    if let error = errorMessage {
                        Text(error)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.red)
                    }
                }
                .padding(.vertical, 48)
                .padding(.bottom, 24)
            }
            
            VStack(spacing: 12) {
                Button {
                    createFamily()
                } label: {
                    Text("Create Family".localized)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            Capsule()
                                .fill(Color.Theme.primaryBlue)
                        )
                        .foregroundStyle(.white)
                }
                .disabled(familyName.isEmpty || isCreating)
                .opacity((familyName.isEmpty || isCreating) ? 0.6 : 1)
                
                Button {
                    onNext()
                } label: {
                    Text("Maybe Later".localized)
                        .font(.system(.body, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .foregroundStyle(Color.Theme.softBrown)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .onAppear {
            familyRepository.setModelContext(modelContext)
        }
        .alert("Error".localized, isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
    }
    
    private func createFamily() {
        let trimmed = familyName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard authService.isOnline else {
            errorMessage = "Requires network connection".localized
            showError = true
            return
        }
        
        isCreating = true
        errorMessage = nil
        
        Task {
            do {
                _ = try await familyRepository.createFamily(name: trimmed)
                await MainActor.run {
                    isCreating = false
                    onNext()
                }
            } catch {
                await MainActor.run {
                    isCreating = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}
