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
    @Environment(\.scenePhase) private var scenePhase
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
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active && authService.isOnline {
                Task { await SyncCoordinator.shared.processPendingSyncItems() }
            }
        }
        .task {
            await authService.initializeAuthState(modelContext: modelContext)
            FriendshipRepository.shared.setModelContext(modelContext)
            InviteRepository.shared.setModelContext(modelContext)
            FamilyRepository.shared.setModelContext(modelContext)
            UserRepository.shared.setModelContext(modelContext)
            TripSessionRepository.shared.setModelContext(modelContext)
            GameInstanceRepository.shared.setModelContext(modelContext)
            TravelLogRepository.shared.setModelContext(modelContext)
            TripActivityEventRepository.shared.setModelContext(modelContext)
            SyncQueueRepository.shared.setModelContext(modelContext)
            TripInviteRepository.shared.setModelContext(modelContext)
            EntitlementService.shared.setModelContext(modelContext)
            let syncCoordinator = SyncCoordinator.shared
            syncCoordinator.setUserSyncExecutor(UserSyncExecutor(authService: authService, userRepository: UserRepository.shared))
            authService.setSyncCoordinator(syncCoordinator)
            let userId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id
            if let userId = userId {
                FriendshipRepository.shared.startListening(userId: userId)
                InviteRepository.shared.startListening(userId: userId)
            }
            EntitlementService.shared.setCurrentUserId(userId)
            await RevenueCatEntitlementBridge.shared.identify(userId: userId)
            if authService.isOnline {
                Task { await SyncCoordinator.shared.processPendingSyncItems() }
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
