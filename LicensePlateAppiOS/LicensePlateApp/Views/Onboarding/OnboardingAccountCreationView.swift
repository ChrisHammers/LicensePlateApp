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
                    
                    Text("Create your RoadTrip Royale identity".localized)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    VStack(alignment: .leading, spacing: 12) {
                         Text("• Compete or Collaborate with Friends & Family".localized)
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                            .padding(.horizontal)
                        HStack(alignment: .top, spacing: 6) {
                            Text("•")
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(Color.Theme.softBrown)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Exclusive Founders Scout avatar (male or female)".localized)
                                    .font(.system(.body, design: .rounded))
                                    .foregroundStyle(Color.Theme.softBrown)
                                Text("Early members only".localized)
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(Color.Theme.softBrown.opacity(0.75))
                            }
                        }
                        .padding(.horizontal)
                        Text("• Your trips saved & synced across devices".localized)
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                            .padding(.horizontal)
                        Text("• Early access to future limited releases".localized)
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 48)
                .padding(.bottom, 24)
            }
            
            VStack(spacing: 20) {
                if let restored = authService.restoredUserInfo {
                    VStack(spacing: 12) {
                        Text(String(format: "We have found the following user, %@-%@, on this device.".localized, restored.userName, restored.email))
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button {
                            coordinator.isExistingAccount = true
                            coordinator.didLogIn = true
                            onNext()
                        } label: {
                            Text(String(format: "Continue as %@".localized, restored.userName))
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
                    }
                }
                
                Button {
                    Task {
                        if authService.restoredUserInfo != nil {
                            try? await authService.signOut()
                            try? authService.resetLocalUserToGuest()
                        }
                        await MainActor.run {
                            coordinator.isExistingAccount = true
                            signInInitialMode = .signIn
                            showSignInSheet = true
                        }
                    }
                } label: {
                    Text((authService.restoredUserInfo != nil ? "Sign In Using Different Account" : "Sign In").localized)
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
                
                VStack(spacing: 4) {
                    Button {
                        Task {
                            if authService.restoredUserInfo != nil {
                                try? await authService.signOut()
                                try? authService.resetLocalUserToGuest()
                            }
                            await MainActor.run {
                                coordinator.isExistingAccount = false
                                signInInitialMode = .createAccount
                                showSignInSheet = true
                            }
                        }
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
                    if coordinator.userType == .captain {
                        Text("Unlocks exclusive Founders Scout avatar".localized)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                    }
                }
                
                if coordinator.userType != .scout {
                    Button {
                        Task {
                            // Always sign out and create fresh anonymous - handles both restored
                            // non-anonymous users AND anonymous users with old Firestore data
                            try? await authService.signOutAndCreateAnonymous()
                            await MainActor.run {
                                coordinator.isExistingAccount = false
                                coordinator.didLogIn = false
                                onNext()
                            }
                        }
                    } label: {
                        Text("Continue as Guest (no sync)".localized)
                            .font(.system(.body, design: .rounded))
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
