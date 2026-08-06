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
    @ObservedObject private var remoteConfig = RemoteConfigService.shared
    var deferredSetupTouchSource: String = "legacy_onboarding"
    let onNext: () -> Void
    
    @State private var showSignInSheet = false
    @State private var signInInitialMode: SignInInitialMode = .signIn
    @State private var showGuestConfirmation = false
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 32) {
                    Text("Account".localized)
                        .font(.system(.largeTitle, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                        .accessibleHeader("Account".localized)
                    
                    Text("Create your RoadTrip Royale identity".localized)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("• Compete or collaborate with your Friends & Family".localized)
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                            .padding(.horizontal)
                        if remoteConfig.founderProgramEnabled {
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
                        }
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
                        .accessibleButton(label: String(format: "Continue as %@".localized, restored.userName), hint: "Continues to next screen".localized)
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
                .accessibleButton(label: (authService.restoredUserInfo != nil ? "Sign In Using Different Account" : "Sign In").localized, hint: "Opens sign in".localized)
                
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
                    .accessibleButton(label: "Create Account".localized, hint: "Opens create account".localized)
                    if remoteConfig.founderProgramEnabled {
                        Text("Unlocks exclusive Founders Scout avatar".localized)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                    }
                }
                
                Button {
                    showGuestConfirmation = true
                } label: {
                    Text("Continue as Guest (no sync)".localized)
                        .font(.system(.body, design: .rounded))
                        .padding(.vertical, 16)
                        .foregroundStyle(Color.Theme.softBrown)
                }
                .accessibleButton(label: "Continue as Guest (no sync)".localized, hint: "Continues as guest without syncing".localized)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .overlay {
            if showGuestConfirmation {
                ConfirmationDialogView(
                    title: "Play without an account?".localized,
                    content: {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("You can continue solo, but you'll miss:".localized)
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(Color.Theme.softBrown)
                                .multilineTextAlignment(.leading)
                            VStack(alignment: .leading, spacing: 8) {
                                if remoteConfig.founderProgramEnabled {
                                    Text("• The exclusive Founders Scout avatar".localized)
                                        .font(.system(.subheadline, design: .rounded))
                                        .foregroundStyle(Color.Theme.softBrown)
                                }
                                Text("• Competing with Friends & Family".localized)
                                    .font(.system(.subheadline, design: .rounded))
                                    .foregroundStyle(Color.Theme.softBrown)
                                Text("• Trip backup & sync".localized)
                                    .font(.system(.subheadline, design: .rounded))
                                    .foregroundStyle(Color.Theme.softBrown)
                                Text("• Early access to future limited releases".localized)
                                    .font(.system(.subheadline, design: .rounded))
                                    .foregroundStyle(Color.Theme.softBrown)
                            }
                            Text("You can always create an account later.".localized)
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(Color.Theme.softBrown)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    },
                    primaryButtonTitle: "Create Account".localized,
                    primaryAction: {
                        showGuestConfirmation = false
                        coordinator.isExistingAccount = false
                        signInInitialMode = .createAccount
                        showSignInSheet = true
                    },
                    secondaryButtonTitle: "Continue as Guest".localized,
                    secondaryAction: {
                        showGuestConfirmation = false
                        continueAsGuest()
                    },
                    onTapOutside: { showGuestConfirmation = false }
                )
            }
        }
        .sheet(isPresented: $showSignInSheet) {
            SignInView(
                authService: authService,
                initialMode: signInInitialMode,
                deferredSetupTouchSource: deferredSetupTouchSource,
                onAuthSuccess: {
                    coordinator.didLogIn = true
                    showSignInSheet = false
                    onNext()
                }
            )
        }
        .onAppear {
            DeferredProfileSetupStore.shared.markTouched(.account, source: deferredSetupTouchSource)
        }
    }
    
    private func continueAsGuest() {
        Task {
            let accountState = FirebaseAccountStateProvider.shared.currentAccountState(for: authService.currentUser)
            if GuestContinuationPolicy.shouldCreateFreshAnonymousSession(accountState: accountState) {
                try? await authService.signOutAndCreateAnonymous()
            }
            await MainActor.run {
                coordinator.isExistingAccount = false
                coordinator.didLogIn = false
                onNext()
            }
        }
    }
}
