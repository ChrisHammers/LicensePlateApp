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
    @ObservedObject private var deepLinkHandler = DeepLinkHandler.shared
    @StateObject private var appCoordinator = AppCoordinator()
    @StateObject private var onboardingCoordinator = OnboardingCoordinator()
    
    @AppStorage("boundariesLoaded") private var boundariesLoaded = false

    private var deepLinkSheetBinding: Binding<DeepLinkDestination?> {
        Binding(
            get: {
                guard appCoordinator.rootView == .main,
                      authService.currentUser != nil else {
                    return nil
                }
                return deepLinkHandler.destination
            },
            set: { deepLinkHandler.destination = $0 }
        )
    }
    
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
        .rewardPopupHost(RewardPresenter.shared)
        .onChange(of: authService.currentUser?.firebaseUID ?? authService.currentUser?.id) { _, newUserId in
            ReturnStreakService.shared.setActiveUserId(newUserId)
            ReturnStreakReminderService.shared.cancelReminder(reason: "user_changed")
            TripActivityEventRecordingService.shared.setProgressionAppendObserver(nil)
            UserProgressionRepository.shared.stopListening()
            UserProgressionService.shared.resetForSignOut()
            AchievementUnlockCelebrationService.shared.resetForSignOut()
            if let newUserId, !newUserId.isEmpty {
                UserProgressionRepository.shared.startListening(userId: newUserId)
                TripActivityEventRecordingService.shared.setProgressionAppendObserver(ProgressionAppendObserverChain.shared)
            }
            if let user = authService.currentUser {
                AchievementUnlockCelebrationService.shared.configure(user: user)
            }
        }
        .onChange(of: scenePhase) { newPhase in
            guard newPhase == .active else { return }
            if authService.isOnline {
                Task { await SyncCoordinator.shared.processPendingSyncItems() }
            }
            if let user = authService.currentUser {
                let entitlement = EntitlementService.shared.entitlementState(for: user)
                Task {
                    await AchievementUnlockSyncService.shared.retryPendingIfNeeded(
                        user: user,
                        entitlement: entitlement
                    )
                }
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
            XpLedgerRepository.shared.setModelContext(modelContext)
            DiscoveryResolutionRepository.shared.setModelContext(modelContext)
            SyncQueueRepository.shared.setModelContext(modelContext)
            try? SyncQueueRepository.shared.resetStuckInProgressSyncItemsToPending()
            TripInviteRepository.shared.setModelContext(modelContext)
            PendingTripLeaveRepository.shared.setModelContext(modelContext)
            UserLifetimeStatsRepository.shared.setModelContext(modelContext)
            UserAchievementRepository.shared.setModelContext(modelContext)
            PublicLifetimeStatsRepository.shared.setModelContext(modelContext)
            FamilyMemberUserIdsRepository.shared.setModelContext(modelContext)
            EntitlementService.shared.setModelContext(modelContext)
            LifetimeStatsCoordinator.shared.authService = authService
            let syncCoordinator = SyncCoordinator.shared
            syncCoordinator.setUserSyncExecutor(UserSyncExecutor(authService: authService, userRepository: UserRepository.shared))
            syncCoordinator.setGameplaySyncOnlineProvider { authService.isOnline }
            // Enables reachability false→true → debounced gameplay queue flush (after repos have ModelContext).
            authService.setSyncCoordinator(syncCoordinator)
            let userId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id
            if let userId = userId {
                FriendshipRepository.shared.startListening(userId: userId)
                InviteRepository.shared.startListening(userId: userId)
                PublicLifetimeStatsRepository.shared.setProfileUserId(userId)
                PublicLifetimeStatsRepository.shared.ensureObservingProfileUser(userId)
                UserProgressionRepository.shared.startListening(userId: userId)
                TripActivityEventRecordingService.shared.setProgressionAppendObserver(ProgressionAppendObserverChain.shared)
            }
            EntitlementService.shared.setCurrentUserId(userId)
            if let user = authService.currentUser {
                AchievementUnlockCelebrationService.shared.configure(user: user)
            }
            await RevenueCatEntitlementBridge.shared.identify(userId: userId)
            if authService.isOnline {
                Task { await SyncCoordinator.shared.processPendingSyncItems() }
            }
            TripParticipationService.shared.bindAuthService(authService)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                boundariesLoaded = true
                appCoordinator.transitionFromSplash()
            }
        }
        .sheet(item: deepLinkSheetBinding) { destination in
            switch destination {
            case .friendInvite(let inviteId):
                FriendInviteDetail(inviteId: inviteId)
                    .environmentObject(authService)
            case .familyInvite(let inviteId, let familyId):
                FamilyInviteDetail(inviteId: inviteId, familyId: familyId, family: nil)
                    .environmentObject(authService)
            case .tripInvite(_):
                PendingTripsView()
                    .environmentObject(authService)
            }
        }
    }
}

#Preview {
    RootView()
        .environmentObject(FirebaseAuthService())
}
