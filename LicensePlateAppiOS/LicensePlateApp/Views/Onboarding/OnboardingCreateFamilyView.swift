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
    var deferredSetupTouchSource: String = "legacy_onboarding"
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
                        .accessibleHeader("Create a Family".localized)
                    
                    Text("Create a family to add Scouts and track your trips together.".localized)
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
                            .accessibleTextField(label: "Family Name".localized, hint: "Enter family name".localized, value: familyName)
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
            
            VStack(spacing: 20) {
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
                .accessibleButton(label: "Create Family".localized, hint: "Creates your family and continues".localized)
                .disabled(familyName.isEmpty || isCreating)
                .opacity((familyName.isEmpty || isCreating) ? 0.6 : 1)
                
                Button {
                    coordinator.switchToJoinFamily()
                } label: {
                    Text("Join a Family".localized)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .overlay(
                            Capsule().stroke(Color.Theme.primaryBlue, lineWidth: 2)
                        )
                        .foregroundStyle(Color.Theme.primaryBlue)
                }
                .accessibleButton(label: "Join a Family".localized, hint: "Opens join family screen".localized)
                
                Button {
                    onNext()
                } label: {
                    Text("Maybe Later".localized)
                        .font(.system(.body, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .foregroundStyle(Color.Theme.softBrown)
                }
                .accessibleButton(label: "Maybe Later".localized, hint: "Skips family setup".localized)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .onAppear {
            familyRepository.setModelContext(modelContext)
            DeferredProfileSetupStore.shared.markTouched(.family, source: deferredSetupTouchSource)
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
