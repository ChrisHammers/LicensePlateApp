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
    @State private var signInInitialMode: SignInInitialMode = .signIn
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 32) {
                    Text("Account".localized)
                        .font(.system(.largeTitle, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                    
                    Text("Sign in to sync across devices, use Friends & Family, and backup your data.".localized)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.vertical, 48)
                .padding(.bottom, 24)
            }
            
            VStack(spacing: 12) {
                Button {
                    coordinator.isExistingAccount = true
                    signInInitialMode = .signIn
                    showSignInSheet = true
                } label: {
                    Text("Sign In".localized)
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
                
                Button {
                    coordinator.isExistingAccount = false
                    signInInitialMode = .createAccount
                    showSignInSheet = true
                } label: {
                    Text("Create Account".localized)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .overlay(
                            Capsule().stroke(Color.Theme.primaryBlue, lineWidth: 2)
                        )
                        .foregroundStyle(Color.Theme.primaryBlue)
                }
                
                if coordinator.userType != .scout {
                    Button {
                        coordinator.isExistingAccount = false
                        coordinator.didLogIn = false
                        onNext()
                    } label: {
                        Text("Continue as Guest".localized)
                            .font(.system(.body, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .foregroundStyle(Color.Theme.softBrown)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .sheet(isPresented: $showSignInSheet) {
            SignInView(
                authService: authService,
                initialMode: signInInitialMode,
                initialBirthYear: signInInitialMode == .createAccount && coordinator.birthYear > 0 ? coordinator.birthYear : nil,
                onAuthSuccess: {
                    coordinator.didLogIn = true
                    showSignInSheet = false
                    onNext()
                }
            )
        }
    }
}
