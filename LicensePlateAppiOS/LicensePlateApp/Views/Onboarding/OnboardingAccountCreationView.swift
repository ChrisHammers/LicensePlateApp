//
//  OnboardingAccountCreationView.swift
//  LicensePlateApp
//
//  Created for Onboarding flow
//

import SwiftUI

struct OnboardingAccountCreationView: View {
    @EnvironmentObject var authService: FirebaseAuthService
    @ObservedObject var coordinator: OnboardingCoordinator
    let onNext: () -> Void
    
    @State private var showSignInSheet = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                Text("Account")
                    .font(.system(.largeTitle, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                
                Text("Sign in to sync across devices, use Friends & Family, and backup your data.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                VStack(spacing: 12) {
                    Button("Sign In") {
                        coordinator.isExistingAccount = true
                        showSignInSheet = true
                    }
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.Theme.primaryBlue, in: Capsule())
                    
                    Button("Create Account") {
                        coordinator.isExistingAccount = false
                        showSignInSheet = true
                    }
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .overlay(
                        Capsule().stroke(Color.Theme.primaryBlue, lineWidth: 2)
                    )
                    
                    if coordinator.userType != .scout {
                        Button("Continue as Guest") {
                            coordinator.isExistingAccount = false
                            coordinator.didLogIn = false
                            onNext()
                        }
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.vertical, 48)
        }
        .sheet(isPresented: $showSignInSheet) {
            SignInView(authService: authService)
                .onDisappear {
                    if authService.isAuthenticated {
                        coordinator.didLogIn = true
                        showSignInSheet = false
                        onNext()
                    }
                }
        }
    }
}
