//
//  QuickSoloStartView.swift
//  LicensePlateApp
//
//  Minimal first-session screen: safety/legal + quick solo trip CTA.
//

import SwiftUI

struct QuickSoloStartView: View {
    @EnvironmentObject private var authService: FirebaseAuthService
    let appCoordinator: AppCoordinator

    @State private var hasAgreedToSafeDriving = false
    @State private var showTerms = false
    @State private var showPrivacy = false
    @State private var showSignInSheet = false
    @State private var signInInitialMode: SignInInitialMode = .signIn
    @State private var isCreatingTrip = false
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "car.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(Color.Theme.primaryBlue)
                        .accessibleDecorative()

                    Text("RoadTrip Royale".localized)
                        .font(.system(.largeTitle, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                        .accessibleHeader("RoadTrip Royale".localized)

                    Text("quick_solo.subtitle".localized)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    safetyCard
                }
                .padding(.vertical, 48)
                .padding(.bottom, 24)
            }

            VStack(spacing: 16) {
                if let restored = authService.restoredUserInfo {
                    VStack(spacing: 12) {
                        Text(String(format: "We have found the following user, %@-%@, on this device.".localized, restored.userName, restored.email))
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                            .multilineTextAlignment(.center)

                        Button {
                            continueAsRestoredUser()
                        } label: {
                            Text(String(format: "Continue as %@".localized, restored.userName))
                                .font(.system(.body, design: .rounded))
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Capsule().fill(Color.Theme.primaryBlue))
                                .foregroundStyle(.white)
                        }
                        .accessibleButton(
                            label: String(format: "Continue as %@".localized, restored.userName),
                            hint: "Continues to next screen".localized
                        )
                        .disabled(!hasAgreedToSafeDriving)
                        .opacity(hasAgreedToSafeDriving ? 1 : 0.6)
                    }
                }

                Button {
                    startQuickSoloTrip()
                } label: {
                    Group {
                        if isCreatingTrip {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Start Quick Solo Trip".localized)
                        }
                    }
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Capsule().fill(Color.Theme.primaryBlue))
                    .foregroundStyle(.white)
                }
                .accessibleButton(
                    label: "Start Quick Solo Trip".localized,
                    hint: "quick_solo.primary_button.hint".localized
                )
                .disabled(!hasAgreedToSafeDriving || isCreatingTrip)
                .opacity(hasAgreedToSafeDriving && !isCreatingTrip ? 1 : 0.6)

                HStack(spacing: 16) {
                    Button {
                        openAuthSheet(mode: .createAccount)
                    } label: {
                        Text("Create Account".localized)
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.medium)
                            .foregroundStyle(Color.Theme.primaryBlue)
                    }
                    .accessibleButton(label: "Create Account".localized, hint: "Opens create account".localized)
                    .disabled(!hasAgreedToSafeDriving)
                    .opacity(hasAgreedToSafeDriving ? 1 : 0.6)

                    Text("·")
                        .foregroundStyle(Color.Theme.softBrown)

                    Button {
                        openAuthSheet(mode: .signIn)
                    } label: {
                        Text((authService.restoredUserInfo != nil ? "Sign In Using Different Account" : "Sign In").localized)
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.medium)
                            .foregroundStyle(Color.Theme.primaryBlue)
                    }
                    .accessibleButton(
                        label: (authService.restoredUserInfo != nil ? "Sign In Using Different Account" : "Sign In").localized,
                        hint: "Opens sign in".localized
                    )
                    .disabled(!hasAgreedToSafeDriving)
                    .opacity(hasAgreedToSafeDriving ? 1 : 0.6)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            FirstSessionAnalyticsService.shared.recordOnboardingStarted(
                flowVariant: .quickSolo,
                offline: !authService.isOnline
            )
            FirstSessionAnalyticsService.shared.recordOnboardingStepViewed(
                stepId: "quick_start",
                stepIndex: 0,
                flowVariant: .quickSolo
            )
            AnalyticsService.shared.logScreenView(screenName: "quick_solo_start")
        }
        .sheet(isPresented: $showSignInSheet) {
            SignInView(
                authService: authService,
                initialMode: signInInitialMode,
                onAuthSuccess: {
                    showSignInSheet = false
                    FirstSessionAnalyticsService.shared.recordOnboardingCompleted(
                        flowVariant: .quickSolo,
                        offline: !authService.isOnline
                    )
                    appCoordinator.completeOnboarding()
                }
            )
        }
        .sheet(isPresented: $showTerms) {
            NavigationStack { TermsView() }
        }
        .sheet(isPresented: $showPrivacy) {
            NavigationStack { PrivacyView() }
        }
        .alert("Error".localized, isPresented: $showError) {
            Button("OK".localized, role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var safetyCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Important Safety Notice".localized)
                .font(.system(.title3, design: .rounded))
                .fontWeight(.bold)
                .foregroundStyle(Color.Theme.primaryBlue)

            Text("Do not use this app while driving.".localized)
                .font(.system(.body, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(Color.Theme.primaryBlue)

            Text("Only use RoadTrip Royale when you are a passenger or when the vehicle is safely parked. Your safety and the safety of others is our top priority.".localized)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)

            HStack(spacing: 0) {
                Text("By continuing, you agree to our ".localized)
                Button("Terms of Service".localized) { showTerms = true }
                    .buttonStyle(.plain)
                    .underline()
                    .accessibleButton(label: "Terms of Service".localized, hint: "Opens Terms of Service".localized)
                Text(" and ".localized)
                Button("Privacy Policy".localized) { showPrivacy = true }
                    .buttonStyle(.plain)
                    .underline()
                    .accessibleButton(label: "Privacy Policy".localized, hint: "Opens Privacy Policy".localized)
                Text(".")
            }
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(Color.Theme.softBrown)

            Button {
                hasAgreedToSafeDriving.toggle()
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: hasAgreedToSafeDriving ? "checkmark.square.fill" : "square")
                        .font(.system(size: 24))
                        .foregroundStyle(hasAgreedToSafeDriving ? Color.Theme.primaryBlue : Color.Theme.softBrown)
                        .accessibleDecorative()
                    Text("I agree to the safe driving mandate, Terms of Service and Privacy Policy".localized)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.Theme.primaryBlue)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibleButton(
                label: "I agree to the safe driving mandate, Terms of Service and Privacy Policy".localized,
                hint: "Double tap to toggle".localized
            )
            .accessibilityValue(hasAgreedToSafeDriving ? "Selected".localized : "")
        }
        .padding()
        .background(Color.Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func openAuthSheet(mode: SignInInitialMode) {
        guard hasAgreedToSafeDriving else { return }
        Task {
            if authService.restoredUserInfo != nil {
                try? await authService.signOut()
                try? authService.resetLocalUserToGuest()
            }
            await MainActor.run {
                signInInitialMode = mode
                showSignInSheet = true
            }
        }
    }

    private func continueAsRestoredUser() {
        guard hasAgreedToSafeDriving else { return }
        FeedbackService.shared.buttonTap()
        FirstSessionAnalyticsService.shared.recordOnboardingCompleted(
            flowVariant: .quickSolo,
            offline: !authService.isOnline
        )
        appCoordinator.completeOnboarding()
    }

    private func ensureGuestSessionForQuickSolo() async throws {
        let accountState = FirebaseAccountStateProvider.shared.currentAccountState(for: authService.currentUser)
        guard !accountState.isGuestLike else { return }
        try await authService.signOut()
        try authService.resetLocalUserToGuest()
        try await authService.signInAnonymously()
    }

    private func startQuickSoloTrip() {
        guard hasAgreedToSafeDriving else { return }
        isCreatingTrip = true
        errorMessage = nil
        FeedbackService.shared.buttonTap()

        Task { @MainActor in
            defer { isCreatingTrip = false }
            do {
                try await ensureGuestSessionForQuickSolo()
                let intent = try QuickSoloTripService.shared.createAndStartQuickSoloTrip(authService: authService)
                FirstSessionAnalyticsService.shared.recordOnboardingCompleted(
                    flowVariant: .quickSolo,
                    offline: !authService.isOnline
                )
                FirstSessionAnalyticsService.shared.recordQuickSoloTripStarted(
                    intent: intent,
                    offline: !authService.isOnline
                )
                Task {
                    await QuickSoloTripService.shared.publishCanonicalToRemote(sessionId: intent.sessionId)
                }
                FeedbackService.shared.actionSuccess()
                appCoordinator.completeQuickStart(launchIntent: intent)
            } catch {
                FeedbackService.shared.actionError()
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

#Preview {
    QuickSoloStartView(appCoordinator: AppCoordinator())
        .environmentObject(FirebaseAuthService())
}
