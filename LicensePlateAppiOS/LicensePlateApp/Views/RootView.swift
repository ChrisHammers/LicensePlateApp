//
//  RootView.swift
//  LicensePlateApp
//
//  Created for Onboarding flow
//

import SwiftUI
import SwiftData

/// Root view that orchestrates Splash → Onboarding → Main App flow
struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authService: FirebaseAuthService
    @StateObject private var appCoordinator = AppCoordinator()
    @StateObject private var onboardingCoordinator = OnboardingCoordinator()
    
    @AppStorage("boundariesLoaded") private var boundariesLoaded = false
    
    var body: some View {
        Group {
            switch appCoordinator.rootView {
            case .splash:
                SplashScreenView()
                    .transition(.opacity)
            case .onboarding:
                OnboardingContainerView(
                    coordinator: onboardingCoordinator,
                    appCoordinator: appCoordinator
                )
                .transition(.opacity)
            case .main:
                ContentView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: appCoordinator.rootView)
        .task {
            await authService.initializeAuthState(modelContext: modelContext)
            FriendshipRepository.shared.setModelContext(modelContext)
            InviteRepository.shared.setModelContext(modelContext)
            FamilyRepository.shared.setModelContext(modelContext)
            UserRepository.shared.setModelContext(modelContext)
            if let userId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id {
                FriendshipRepository.shared.startListening(userId: userId)
                InviteRepository.shared.startListening(userId: userId)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                boundariesLoaded = true
                appCoordinator.transitionFromSplash()
            }
        }
    }
}

#Preview {
    RootView()
        .environmentObject(FirebaseAuthService())
}
