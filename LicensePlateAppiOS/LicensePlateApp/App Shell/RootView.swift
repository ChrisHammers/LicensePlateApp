//
//  RootView.swift
//  LicensePlateApp
//
//  Created for Onboarding flow
//

import SwiftUI
import SwiftData

/// Root view that orchestrates Splash → Force Update / Quick Start / Legacy Onboarding → Main App flow
struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var authService: FirebaseAuthService
    @ObservedObject private var deepLinkHandler = DeepLinkHandler.shared
    @StateObject private var appCoordinator = AppCoordinator()
    @StateObject private var onboardingCoordinator = OnboardingCoordinator()
    @ObservedObject private var remoteConfig = RemoteConfigService.shared
    @ObservedObject private var appUpdateGate = AppUpdateGateService.shared

    @AppStorage("boundariesLoaded") private var boundariesLoaded = false
    @State private var showSoftUpdateSheet = false

    private var deepLinkSheetBinding: Binding<DeepLinkDestination?> {
        Binding(
            get: {
                guard appCoordinator.rootView == .main,
                      authService.currentUser != nil else {
                    return nil
                }
                // Trip session opens via MainCoordinator in ContentView (not a sheet).
                if case .tripSession = deepLinkHandler.destination {
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
            case .forceUpdate:
                ForceUpdateView(mode: .hard, gate: appUpdateGate)
                    .transition(.opacity)
            case .quickStart:
                OnboardingContainerBackground {
                    QuickSoloStartView(appCoordinator: appCoordinator)
                }
                .transition(.opacity)
            case .legacyOnboarding:
                OnboardingContainerView(
                    coordinator: onboardingCoordinator,
                    appCoordinator: appCoordinator
                )
                .transition(.opacity)
            case .main:
                ContentView(appCoordinator: appCoordinator)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: appCoordinator.rootView)
        .onChange(of: authService.currentUser?.firebaseUID ?? authService.currentUser?.id) { _, newUserId in
            ReturnStreakService.shared.setActiveUserId(newUserId)
            ReturnStreakReminderService.shared.cancelReminder(reason: "user_changed")
            TripActivityEventRecordingService.shared.setProgressionAppendObserver(nil)
            UserProgressionRepository.shared.stopListening()
            XpGrantRemoteRepository.shared.stopListening()
            UserProgressionService.shared.resetForSignOut()
            XpGrantReconcileService.shared.resetForSignOut()
            AchievementUnlockCelebrationService.shared.resetForSignOut()
            XpGainToastService.shared.resetForSignOut()
            if let newUserId, !newUserId.isEmpty {
                FriendshipRepository.shared.startListening(userId: newUserId)
                InviteRepository.shared.startListening(userId: newUserId)
                SocialInboxBadgeService.shared.bind(
                    userId: newUserId,
                    activeFamilyId: authService.currentUser?.activeFamilyId
                )
                UserProgressionRepository.shared.startListening(userId: newUserId)
                XpGrantRemoteRepository.shared.startListening(userId: newUserId)
                TripActivityEventRecordingService.shared.setProgressionAppendObserver(ProgressionAppendObserverChain.shared)
                Task {
                    await FirebaseMessagingService.shared.refreshAndPersistTokenIfPossible()
                }
                if authService.isOnline {
                    Task {
                        _ = await XpGrantReconcileService.shared.reconcileIfNeeded(
                            userId: newUserId,
                            isOnline: authService.isOnline
                        )
                    }
                }
            } else {
                FriendshipRepository.shared.stopListening()
                InviteRepository.shared.stopListening()
                SocialInboxBadgeService.shared.bind(userId: nil, activeFamilyId: nil)
            }
            if let user = authService.currentUser {
                AchievementUnlockCelebrationService.shared.configure(user: user)
            }
            XpGainToastService.shared.configure(userId: newUserId)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background, !appCoordinator.hasSeenOnboarding {
                let variant = FirstSessionState.shared.activeFlowVariant ?? .quickSolo
                FirstSessionAnalyticsService.shared.recordOnboardingAbandoned(flowVariant: variant)
            }
            guard newPhase == .active else { return }
            if authService.isOnline {
                Task { await SyncCoordinator.shared.processPendingSyncItems() }
            }
            if let user = authService.currentUser {
                let entitlement = EntitlementService.shared.entitlementState(for: user)
                let userId = user.firebaseUID ?? user.id
                Task {
                    await AchievementUnlockSyncService.shared.retryPendingIfNeeded(
                        user: user,
                        entitlement: entitlement
                    )
                    if !userId.isEmpty {
                        await ReturnStreakDailyXpClaimService.shared.retryPendingIfNeeded(userId: userId)
                    }
                }
            }
        }
        .task {
            let splashStartedAt = Date()
            await remoteConfig.fetchAndActivate()
            appUpdateGate.refresh(remoteConfig: remoteConfig)

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
            TripRoutePointRepository.shared.setModelContext(modelContext)
            PublicLifetimeStatsRepository.shared.setModelContext(modelContext)
            FamilyMemberUserIdsRepository.shared.setModelContext(modelContext)
            FriendUserIdsRepository.shared.setModelContext(modelContext)
            LocalPlayIdentityRepository.shared.setModelContext(modelContext)
            EntitlementService.shared.setModelContext(modelContext)
            LifetimeStatsCoordinator.shared.authService = authService
            let syncCoordinator = SyncCoordinator.shared
            syncCoordinator.setUserSyncExecutor(UserSyncExecutor(authService: authService, userRepository: UserRepository.shared))
            syncCoordinator.setGameplaySyncOnlineProvider { authService.isOnline }
            // F-6 (FR-28): unconsented-child restriction — gameplay uploads hold until
            // family admission; the restriction is keyed to the declared identity.
            // F-18 (FR-60(a)): the uid provider is deliberately `firebaseUID` ONLY — not the
            // `?? id` fallback used elsewhere for the play identity. An under-13 player now
            // has no uid for the whole time they play locally, and feeding the local UUID in
            // here sends `childSessionState` down its signed-in branch, where the UUID
            // matches no declared/pending uid and no server flag, and the session classifies
            // `.notChild`. That would take away the FR-28 banner — the child's only route to
            // share-code entry — from exactly the population it exists for. A nil uid instead
            // reaches the pre-uid provisional branch below it, which reads the epoch's
            // under-13 answer and correctly returns `.unconsentedChild`.
            ChildRestrictedModeService.shared.configure(
                currentUserIdProvider: { authService.currentUser?.firebaseUID },
                activeFamilyIdProvider: { authService.currentUser?.activeFamilyId },
                // Server-resolved child truth: keeps the restriction classified from
                // `users/{uid}` even after a manager correction wiped the device's
                // age-gate markers (correct → re-grant → remove) or on a device that
                // never ran the gate for this account.
                resolvedIsChildAccountProvider: { UserRepository.shared.isChildAccount(for: $0) },
                // FR-88: server truth for "a family is deciding about me". Tri-state, and
                // the nil case matters — an unanswered projection keeps the device's
                // optimistic redemption flag in charge instead of retiring it.
                serverPendingFamilyRequestProvider: {
                    UserRepository.shared.hasPendingFamilyRequest(for: $0)
                }
            )
            syncCoordinator.setGameplayCloudSyncHoldProvider {
                ChildRestrictedModeService.shared.isGameplayCloudSyncPaused
            }
            // F-8 fix: the consent edge (activeFamilyId nil ⇄ set) drives the queue
            // resume and the awaiting-approval invite bookkeeping.
            FamilyMembershipTransitionService.shared.configure(
                dependencies: .live(
                    currentUserIdProvider: {
                        authService.currentUser?.firebaseUID ?? authService.currentUser?.id
                    }
                )
            )
            // FR-28 consent resume + durable recovery need the signed-in identity, which
            // lives here. Identity only — the repository reads stay in the service layer.
            ConsentRecoverySupport.contextProvider = {
                guard let user = authService.currentUser else { return nil }
                return ConsentRecoverySupport.Context(
                    user: user,
                    userId: user.firebaseUID ?? user.id,
                    isOnline: authService.isOnline
                )
            }
            authService.setSyncCoordinator(syncCoordinator)
            let userId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id
            let activeFamilyId = authService.currentUser?.activeFamilyId
            if let userId = userId {
                FriendshipRepository.shared.startListening(userId: userId)
                InviteRepository.shared.startListening(userId: userId)
                SocialInboxBadgeService.shared.bind(userId: userId, activeFamilyId: activeFamilyId)
                PublicLifetimeStatsRepository.shared.setProfileUserId(userId)
                PublicLifetimeStatsRepository.shared.ensureObservingProfileUser(userId)
                UserProgressionRepository.shared.startListening(userId: userId)
                XpGrantRemoteRepository.shared.startListening(userId: userId)
                TripActivityEventRecordingService.shared.setProgressionAppendObserver(ProgressionAppendObserverChain.shared)
                if authService.isOnline {
                    Task {
                        _ = await XpGrantReconcileService.shared.reconcileIfNeeded(
                            userId: userId,
                            isOnline: authService.isOnline
                        )
                    }
                }
            } else {
                SocialInboxBadgeService.shared.bind(userId: nil, activeFamilyId: nil)
            }
            EntitlementService.shared.setCurrentUserId(userId)
            if let user = authService.currentUser {
                AchievementUnlockCelebrationService.shared.configure(user: user)
            }
            XpGainToastService.shared.configure(userId: userId)
            // COPPA F-9 (FR-46): RevenueCat identification is owned by
            // `DeferredSDKStartupService`, driven from the posture routine that
            // `initializeAuthState` above already ran. Identifying here would start the
            // SDK for age-unresolved sessions, which is exactly what FR-46 forbids.
            if authService.isOnline {
                Task { await SyncCoordinator.shared.processPendingSyncItems() }
                // FR-28 safety net: a consent edge only fires while the app is running, so
                // data dropped before a restriction lifted has no other second chance.
                // Idempotent, once per launch, and skipped entirely while restricted.
                Task { await ChildRestrictedDataRecoveryService.shared.runLaunchRecoveryIfEligible() }
            }
            TripParticipationService.shared.bindAuthService(authService)

            await leaveSplashWhenReady(startedAt: splashStartedAt)
        }
        .sheet(isPresented: $showSoftUpdateSheet, onDismiss: {
            // Swipe-dismiss still records soft dismiss for this fingerprint.
            if appUpdateGate.shouldPresentSoftPrompt {
                appUpdateGate.dismissSoft()
            }
        }) {
            ForceUpdateView(mode: .soft, gate: appUpdateGate) {
                showSoftUpdateSheet = false
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: deepLinkSheetBinding) { destination in
            switch destination {
            case .friendInvite(let inviteId):
                if FriendsFamilyAccessPolicy.shared.canUseFriendsAndFamily(for: authService.currentUser) {
                    FriendInviteDetail(inviteId: inviteId)
                        .environmentObject(authService)
                } else {
                    NavigationStack {
                        FriendsFamilySignUpGateView(feature: .friends)
                            .environmentObject(authService)
                    }
                }
            case .familyInvite(let inviteId, let familyId):
                if FriendsFamilyAccessPolicy.shared.canUseFriendsAndFamily(for: authService.currentUser) {
                    FamilyInviteDetail(inviteId: inviteId, familyId: familyId, family: nil)
                        .environmentObject(authService)
                } else {
                    NavigationStack {
                        FriendsFamilySignUpGateView(feature: .family)
                            .environmentObject(authService)
                    }
                }
            case .tripInvite(_):
                PendingTripsView()
                    .environmentObject(authService)
            case .familyPendingApprovals(let familyId):
                if FriendsFamilyAccessPolicy.shared.canUseFriendsAndFamily(for: authService.currentUser) {
                    FamilyPendingApprovals(familyId: familyId)
                        .environmentObject(authService)
                } else {
                    NavigationStack {
                        FriendsFamilySignUpGateView(feature: .family)
                            .environmentObject(authService)
                    }
                }
            case .familyHome:
                if FriendsFamilyAccessPolicy.shared.canUseFriendsAndFamily(for: authService.currentUser) {
                    NavigationStack {
                        FamilyDashboard()
                            .environmentObject(authService)
                    }
                } else {
                    NavigationStack {
                        FriendsFamilySignUpGateView(feature: .family)
                            .environmentObject(authService)
                    }
                }
            case .tripSession:
                EmptyView()
            }
        }
    }

    /// Honors splash minimum delay after RC fetch + update-policy refresh, then gates or continues.
    private func leaveSplashWhenReady(startedAt: Date) async {
        let minimumDelay = Double(remoteConfig.quickSoloSplashDelayMs) / 1000.0
        let elapsed = Date().timeIntervalSince(startedAt)
        let remaining = max(0, minimumDelay - elapsed)
        if remaining > 0 {
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
        }

        boundariesLoaded = true

        if appUpdateGate.decision.isHard {
            appCoordinator.showForceUpdate()
            return
        }

        appCoordinator.transitionFromSplash(quickSoloEnabled: remoteConfig.quickSoloFirstSessionEnabled)
        if appUpdateGate.shouldPresentSoftPrompt {
            showSoftUpdateSheet = true
        }
    }
}

/// Shared onboarding background wrapper for quick start screen.
private struct OnboardingContainerBackground<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            if let imageName = AppPreferences.backgroundImageName(style: .paths, colorScheme: colorScheme) {
                Image(imageName)
                    .resizable()
                    .ignoresSafeArea()
            } else {
                Color.Theme.background
                    .ignoresSafeArea()
            }
            content()
        }
    }
}

#Preview {
    RootView()
        .environmentObject(FirebaseAuthService())
}
