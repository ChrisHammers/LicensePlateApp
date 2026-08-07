//
//  ContentView.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import SwiftUI
import SwiftData
import Combine
import CoreLocation
import AVFoundation
import UserNotifications
import Speech

struct ContentView: View {
    @ObservedObject var appCoordinator: AppCoordinator
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authService: FirebaseAuthService
    @StateObject private var mainCoordinator = MainCoordinator()
    @StateObject private var activeTripsListViewModel = ActiveTripsListViewModel(
        tripSessionRepository: TripSessionRepository.shared,
        tripActivityEventRepository: TripActivityEventRepository.shared,
        gameInstanceRepository: GameInstanceRepository.shared,
        lifecycleService: TripSessionLifecycleService.shared
    )
    @State private var isShowingCreateSheet = false
    @State private var isShowingSettings = false
//    @State private var isShowingPendingInvites = false
    @State private var isShowingTravelLog = false
    @StateObject private var pendingTripsViewModel = PendingTripsViewModel(
        tripInviteRepository: TripInviteRepository.shared,
        authService: FirebaseAuthService()
    )
    @StateObject private var tripLimitPaywallViewModel = PaywallViewModel()
    @StateObject private var travelLogViewModel = TravelLogViewModel(
        travelLogRepository: TravelLogRepository.shared,
        tripSessionRepository: TripSessionRepository.shared,
        gameInstanceRepository: GameInstanceRepository.shared,
        tripActivityEventRepository: TripActivityEventRepository.shared,
        authService: FirebaseAuthService()
    )
    @StateObject private var returnStreakViewModel = ReturnStreakViewModel()
    @ObservedObject private var deepLinkHandler = DeepLinkHandler.shared
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("boundariesLoaded") private var boundariesLoaded = false
    @AppStorage(FirstSessionStateKeys.hasLoggedFirstFind) private var hasLoggedFirstFind = false
    @ObservedObject private var deferredSetupStore = DeferredProfileSetupStore.shared
    @State private var showDeferredSetupBanner = false
    @State private var isShowingDeferredSetupHub = false
    
    // Custom detent for the new trip sheet - device-aware sizing
    // On iPad, use a larger fraction since 25% is too small to show the text field
    private var smallDetent: PresentationDetent {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return PresentationDetent.fraction(0.4) // 40% on iPad
        } else {
            return PresentationDetent.fraction(0.25) // 25% on iPhone
        }
    }
    @State private var sheetDetent: PresentationDetent = {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return PresentationDetent.fraction(0.4)
        } else {
            return PresentationDetent.fraction(0.25)
        }
    }()
    
    // App Preferences
    @AppStorage("appDarkMode") private var appDarkModeRaw: String = AppDarkMode.system.rawValue
    @AppStorage("appPlaySoundEffects") private var appPlaySoundEffects = true
    @AppStorage("appUseVibrations") private var appUseVibrations = true
    
    // Computed property for color scheme
    private var currentColorScheme: ColorScheme? {
        AppPreferences.colorSchemeFromPreference(rawValue: appDarkModeRaw)
    }

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

  @MainActor
  init(appCoordinator: AppCoordinator) {
        self.appCoordinator = appCoordinator
    UINavigationBar.appearance().titleTextAttributes = [.foregroundColor: Color.Theme.primaryBlue.uiColor]
     }
    var body: some View {
        ZStack {
            if boundariesLoaded {
              mainHomeNavigationStack
              .environmentObject(mainCoordinator)
              .transition(.opacity)
            } else {
                SplashScreenView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: boundariesLoaded)
        .preferredColorScheme(currentColorScheme)
        .onAppear {
            FeedbackService.shared.updatePreferences(hapticEnabled: appUseVibrations, soundEnabled: appPlaySoundEffects)
            
            // Mark boundaries as loaded after splash screen has rendered
            // This ensures the splash screen is visible before transitioning
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                // Boundaries are already loaded in AppDelegate, so we can safely mark as complete
                boundariesLoaded = true
            }
        }
        .onChange(of: appUseVibrations) { _, newValue in
            FeedbackService.shared.updatePreferences(hapticEnabled: newValue, soundEnabled: appPlaySoundEffects)
        }
        .onChange(of: appPlaySoundEffects) { _, newValue in
            FeedbackService.shared.updatePreferences(hapticEnabled: appUseVibrations, soundEnabled: newValue)
        }
    }

    /// Split from `body` so the Swift compiler can type-check the main scene in reasonable time.
    private var mainHomeNavigationStack: some View {
        NavigationStack(path: $mainCoordinator.path) {
            homeTripRecapWithLifecycle
                .navigationDestination(for: MainCoordinator.MainRoute.self) { route in
                    homeRouteDestination(route: route)
                }
        }
    }

    private var currentUserId: String? {
        authService.currentUser?.firebaseUID ?? authService.currentUser?.id
    }

    private var homeTripRecapCore: some View {
        TripEndRecapHost(
            mainCoordinator: mainCoordinator,
            travelLogViewModel: travelLogViewModel,
            activeTripsListViewModel: activeTripsListViewModel
        ) {
            AppBackgroundView {
                homeTripAndInvitesList
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            HomeNavigationToolbar(
                streakPresentation: returnStreakViewModel.presentation,
                isStreakVisible: returnStreakViewModel.presentation.isVisible,
                displayName: authService.currentUser?.userName,
                currentUser: authService.currentUser,
                onStreakTap: { returnStreakViewModel.openExplanation() },
                onTravelLogTap: { isShowingTravelLog = true },
                onSettingsTap: { isShowingSettings = true }
            )
        }
    }

    private var homeTripRecapWithPresentation: some View {
        homeTripRecapPresentationOverlays
    }

    private var homeTripRecapPresentationSheets: some View {
        homeTripRecapCore
            .sheet(isPresented: $isShowingSettings) {
                DefaultSettingsView()
                    .environmentObject(authService)
            }
            .sheet(isPresented: $isShowingTravelLog) {
                TravelLogView(viewModel: travelLogViewModel)
                    .environmentObject(authService)
            }
            .sheet(isPresented: $returnStreakViewModel.isShowingExplanation) {
                ReturnStreakExplanationSheet(currentStreak: returnStreakViewModel.presentation.currentStreak)
            }
            .sheet(isPresented: $isShowingCreateSheet) {
                homeCreateTripSheet
            }
            .sheet(isPresented: tripLimitPaywallPresented) {
                PaywallView(
                    viewModel: tripLimitPaywallViewModel,
                    onDismiss: { pendingTripsViewModel.dismissTripLimitPaywall() },
                    source: TripLimitGateSource.inviteAccept.rawValue
                )
                .onAppear {
                    tripLimitPaywallViewModel.setTripLimitContext()
                }
            }
    }

    private var homeTripRecapPresentationOverlays: some View {
        homeTripRecapPresentationSheets
            .alert("Error".localized, isPresented: activeTripsDeleteErrorPresented) {
                Button("OK".localized, role: .cancel) { activeTripsListViewModel.clearError() }
                Button("Retry".localized) {
                    AnalyticsService.shared.log(.persistenceRetryTapped(context: "active_list_delete"))
                    activeTripsListViewModel.retryLastDelete()
                }
            } message: {
                if let msg = activeTripsListViewModel.errorMessage {
                    Text(msg)
                }
            }
            .overlay {
                if authService.showUsernameConflictDialog {
                    UsernameConflictDialog(authService: authService)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                addTripButton
            }
            .overlay(alignment: .top) {
                if showDeferredSetupBanner {
                    deferredSetupBanner
                }
            }
            .sheet(isPresented: $isShowingDeferredSetupHub, onDismiss: {
                refreshDeferredSetupBanner()
            }) {
                NavigationStack {
                    DeferredProfileSetupHubView()
                        .environmentObject(authService)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done".localized) { isShowingDeferredSetupHub = false }
                            }
                        }
                }
            }
    }

    private var homeTripRecapWithLifecycle: some View {
        homeTripRecapLifecycleObservers
    }

    /// First half of home lifecycle modifiers (keeps type-checking tractable).
    private var homeTripRecapLifecycleCore: some View {
        homeTripRecapWithPresentation
            .onChange(of: currentUserId) { _, newUserId in
                handleCurrentUserIdChange(newUserId)
            }
            .onChange(of: authService.currentUser?.activeFamilyId) { _, newFamilyId in
                handleActiveFamilyIdChange(newFamilyId)
            }
            .onChange(of: scenePhase) { _, phase in
                handleHomeScenePhaseChange(phase)
            }
            .task {
                await bootstrapHomeScreen()
            }
            .onReceive(TripCanonicalRemoteSyncService.shared.hydrationSignal) { _ in
                handleTripHydrationSignal()
            }
            .onReceive(NotificationCenter.default.publisher(for: .accountWillHardSignOut)) { _ in
                handleHardSignOutWillBegin()
            }
            .onReceive(NotificationCenter.default.publisher(for: .accountDidHardSignOut)) { _ in
                handleHardSignOutUIReset()
            }
            .onAppear {
                handleHomeOnAppear()
            }
    }

    /// Second half of home lifecycle modifiers.
    private var homeTripRecapLifecycleObservers: some View {
        homeTripRecapLifecycleCore
            .onChange(of: deepLinkHandler.destination) { _, destination in
                handleDeepLinkDestinationChange(destination)
            }
            .onChange(of: hasLoggedFirstFind) { _, _ in
                refreshDeferredSetupBanner()
            }
            .onChange(of: mainCoordinator.path.count) { _, _ in
                refreshDeferredSetupBanner()
            }
            .onChange(of: deferredSetupStore.revision) { _, _ in
                refreshDeferredSetupBanner()
            }
            .onChange(of: authService.currentUser?.id) { _, _ in
                refreshDeferredSetupBanner()
            }
            .onChange(of: isShowingCreateSheet) { _, isShowing in
                handleCreateSheetVisibilityChange(isShowing)
            }
    }

    private var homeCreateTripSheet: some View {
        NewTripFlowView(
            authService: authService,
            onCreated: { session in
                mainCoordinator.openSession(session.id)
                isShowingCreateSheet = false
                activeTripsListViewModel.load(userId: currentUserId)
            }
        )
        .environmentObject(authService)
        .presentationDetents([.large], selection: $sheetDetent)
        .presentationDragIndicator(.visible)
        .onAppear {
            sheetDetent = smallDetent
        }
    }

    private var tripLimitPaywallPresented: Binding<Bool> {
        Binding(
            get: { pendingTripsViewModel.shouldPresentTripLimitPaywall },
            set: { if !$0 { pendingTripsViewModel.dismissTripLimitPaywall() } }
        )
    }

    private var activeTripsDeleteErrorPresented: Binding<Bool> {
        Binding(
            get: { activeTripsListViewModel.errorMessage != nil },
            set: { if !$0 { activeTripsListViewModel.clearError() } }
        )
    }

    @ViewBuilder
    private func homeRouteDestination(route: MainCoordinator.MainRoute) -> some View {
        switch route {
        case .session(let sessionId):
            if activeTripsListViewModel.session(for: sessionId) != nil {
                TripSessionView(sessionId: sessionId, authService: authService)
            } else {
                TripMissingView()
            }
        case .game(let sessionId, let gameId):
            if let (session, game) = activeTripsListViewModel.sessionAndGame(sessionId: sessionId, gameId: gameId) {
                LicensePlateGameView(session: session, game: game, authService: authService)
            } else {
                TripMissingView()
            }
        }
    }

    private func handleHomeScenePhaseChange(_ phase: ScenePhase) {
        guard phase == .active else { return }
        ensureSocialInboxListening(
            userId: currentUserId,
            activeFamilyId: authService.currentUser?.activeFamilyId
        )
        returnStreakViewModel.refresh()
        ReturnStreakReminderService.shared.logReminderOpenedIfNeeded(userId: currentUserId)
        Task {
            await ReturnStreakReminderService.shared.refreshScheduleIfNeeded(userId: currentUserId)
        }
    }

    /// Deep links present from RootView (invite sheets) or navigate via MainCoordinator
    /// (trip session). Competing ContentView sheets block RootView presentation, so dismiss
    /// them first; when a sheet was up, republish the destination so `.sheet(item:)` retries.
    private func handleDeepLinkDestinationChange(_ destination: DeepLinkDestination?) {
        guard let destination else { return }

        let dismissedCompetingSheet = dismissCompetingHomeSheetsIfNeeded()

        if case .tripSession = destination {
            handleTripSessionDeepLink(destination)
            return
        }

        if dismissedCompetingSheet {
            republishDeepLinkAfterDismissingHomeSheets(destination)
        }
    }

    @discardableResult
    private func dismissCompetingHomeSheetsIfNeeded() -> Bool {
        let hadSheet = isShowingSettings
            || isShowingTravelLog
            || isShowingCreateSheet
            || isShowingDeferredSetupHub
            || returnStreakViewModel.isShowingExplanation
            || pendingTripsViewModel.shouldPresentTripLimitPaywall

        guard hadSheet else { return false }

        isShowingSettings = false
        isShowingTravelLog = false
        isShowingCreateSheet = false
        isShowingDeferredSetupHub = false
        returnStreakViewModel.isShowingExplanation = false
        pendingTripsViewModel.dismissTripLimitPaywall()
        return true
    }

    private func republishDeepLinkAfterDismissingHomeSheets(_ destination: DeepLinkDestination) {
        deepLinkHandler.clearDestination()
        Task { @MainActor in
            // Let competing ContentView sheets finish dismissing before RootView presents.
            try? await Task.sleep(for: .milliseconds(150))
            // Avoid clobbering a newer deep link that arrived while sheets were dismissing.
            if deepLinkHandler.destination == nil {
                deepLinkHandler.destination = destination
            }
        }
    }

    private func handleTripSessionDeepLink(_ destination: DeepLinkDestination) {
        guard case .tripSession(let tripSessionId) = destination else { return }
        guard let sessionId = UUID(uuidString: tripSessionId) else { return }
        activeTripsListViewModel.load(userId: currentUserId)
        mainCoordinator.openSession(sessionId)
        deepLinkHandler.clearDestination()
    }

    private func handleCurrentUserIdChange(_ newUserId: String?) {
        returnStreakViewModel.bind(userId: newUserId)
        ensureSocialInboxListening(
            userId: newUserId,
            activeFamilyId: authService.currentUser?.activeFamilyId
        )
        activeTripsListViewModel.load(userId: newUserId)
        if let newUserId, !newUserId.isEmpty {
            pendingTripsViewModel.loadIfNeeded()
        } else {
            TripInviteRepository.shared.stopListening()
        }
        NotificationRoutingService.shared.ensureObserving(userId: newUserId)
    }

    private func handleHardSignOutWillBegin() {
        mainCoordinator.resetPendingState()
        isShowingSettings = false
        isShowingTravelLog = false
        isShowingCreateSheet = false
    }

    private func handleHardSignOutUIReset() {
        activeTripsListViewModel.load(userId: currentUserId)
        pendingTripsViewModel.loadIfNeeded()
        NotificationRoutingService.shared.ensureObserving(userId: currentUserId)
    }

    private func handleActiveFamilyIdChange(_ newFamilyId: String?) {
        ensureSocialInboxListening(userId: currentUserId, activeFamilyId: newFamilyId)
    }

    private func handleTripHydrationSignal() {
        activeTripsListViewModel.load(userId: currentUserId)
        TripEndRecapSupport.startMultiplayerListeners(for: activeTripsListViewModel.items)
    }

    private func handleHomeOnAppear() {
        pendingTripsViewModel.setAuthService(authService)
        travelLogViewModel.setAuthService(authService)
        returnStreakViewModel.bind(userId: currentUserId)
        ensureSocialInboxListening(
            userId: currentUserId,
            activeFamilyId: authService.currentUser?.activeFamilyId
        )
        NotificationRoutingService.shared.ensureObserving(userId: currentUserId)
        let userId = currentUserId
        Task {
            if let userId, !userId.isEmpty {
                await NotificationPrefsStore.shared.load(userId: userId)
                await AppPrefsStore.shared.load(userId: userId)
            }
            await ReturnStreakReminderService.shared.refreshScheduleIfNeeded(userId: userId)
        }
        refreshDeferredSetupBanner()
    }

    private func handleCreateSheetVisibilityChange(_ isShowing: Bool) {
        guard !isShowing else { return }
        activeTripsListViewModel.load(userId: currentUserId)
    }

    /// Keep invite listeners + badge projection aligned with the signed-in user / active family.
    private func ensureSocialInboxListening(userId: String?, activeFamilyId: String?) {
        if let userId, !userId.isEmpty {
            FriendshipRepository.shared.startListening(userId: userId)
            InviteRepository.shared.startListening(userId: userId)
        } else {
            FriendshipRepository.shared.stopListening()
            InviteRepository.shared.stopListening()
        }
        SocialInboxBadgeService.shared.bind(userId: userId, activeFamilyId: activeFamilyId)
    }

  private func bootstrapHomeScreen() async {
        // RootView completes auth and repository setup before presenting ContentView.
        // Load local trips immediately instead of blocking them behind a second
        // Firestore profile hydration.
        activeTripsListViewModel.load(userId: currentUserId)

        FriendshipRepository.shared.setModelContext(modelContext)
        InviteRepository.shared.setModelContext(modelContext)
        FamilyRepository.shared.setModelContext(modelContext)
        UserRepository.shared.setModelContext(modelContext)
        TripSessionRepository.shared.setModelContext(modelContext)
        GameInstanceRepository.shared.setModelContext(modelContext)
        TravelLogRepository.shared.setModelContext(modelContext)
        TripActivityEventRepository.shared.setModelContext(modelContext)
        TripInviteRepository.shared.setModelContext(modelContext)
        EntitlementService.shared.setModelContext(modelContext)

        pendingTripsViewModel.setAuthService(authService)
        ensureSocialInboxListening(
            userId: currentUserId,
            activeFamilyId: authService.currentUser?.activeFamilyId
        )
        pendingTripsViewModel.loadIfNeeded()
        TripEndRecapSupport.startMultiplayerListeners(for: activeTripsListViewModel.items)
        returnStreakViewModel.bind(userId: currentUserId)
        await ReturnStreakReminderService.shared.refreshScheduleIfNeeded(userId: currentUserId)
        for item in activeTripsListViewModel.items where item.session.status == .active {
            await ReminderNotificationService.shared.scheduleInactiveActiveTripReminder(
                sessionId: item.session.id,
                tripName: item.session.name
            )
        }
        handleQuickSoloLaunchIfNeeded()
    }

    private func handleQuickSoloLaunchIfNeeded() {
        guard let intent = appCoordinator.consumePendingQuickSoloLaunch() else { return }
        activeTripsListViewModel.load(userId: currentUserId)
        mainCoordinator.openGame(sessionId: intent.sessionId, gameId: intent.gameId)
    }

    private func refreshDeferredSetupBanner() {
        let shouldShow = deferredSetupStore.shouldShowPostFirstFindPrompt(for: authService.currentUser)
        if shouldShow, !showDeferredSetupBanner {
            let pending = deferredSetupStore.pendingSteps(for: authService.currentUser)
            FirstSessionAnalyticsService.shared.recordDeferredSetupPromptShown(pendingSteps: pending)
        }
        showDeferredSetupBanner = shouldShow
    }

    private var deferredSetupBanner: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Complete your profile".localized)
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                Text("deferred_setup.banner.subtitle".localized)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
            }
            Spacer(minLength: 8)
            Button {
                isShowingDeferredSetupHub = true
                FirstSessionAnalyticsService.shared.recordDeferredSetupStepOpened(
                    stepId: "hub",
                    source: "post_first_find_banner"
                )
            } label: {
                Text("Open".localized)
                    .font(.system(.caption, design: .rounded))
                    .fontWeight(.semibold)
            }
            .accessibleButton(label: "Open".localized, hint: "Opens profile setup".localized)
            Button {
                deferredSetupStore.dismissPostFirstFindPrompt()
                showDeferredSetupBanner = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.Theme.softBrown)
            }
            .accessibleButton(label: "Dismiss".localized, hint: "Hides this reminder".localized)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.Theme.cardBackground)
                .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
    }

    private var homeTripAndInvitesList: some View {
        List {
            Section {
                header
                    .listRowInsets(.init(top: 24, leading: 20, bottom: 24, trailing: 20))
                    .listRowBackground(Color.clear)
            }
            .textCase(nil)

            if activeTripsListViewModel.items.isEmpty {
                Section {
                    activeTripEmptyCard
                        .listRowInsets(.init(top: 0, leading: 20, bottom: 24, trailing: 20))
                        .listRowBackground(Color.clear)
                } header: {
                    Text("Active Trips".localized)
                } footer: {
                    activeTripsPendingLeaveFooter
                }
                .textCase(nil)
            } else {
                Section {
                    activeSessionList
                } header: {
                    Text("Active Trips".localized)
                } footer: {
                    activeTripsPendingLeaveFooter
                }
                .textCase(nil)
                .listRowBackground(Color.clear)
            }

            Section {
                if pendingTripsViewModel.incomingInvites.isEmpty {
                    pendingInvitesEmptyCard
                } else {
                    ForEach(pendingTripsViewModel.incomingInvites, id: \.inviteId) { invite in
                        PendingInviteCard(
                            invite: invite,
                            snapshot: pendingTripsViewModel.displaySnapshot(for: invite, isIncoming: true),
                            isIncoming: true,
                            isAcceptBusy: pendingTripsViewModel.isBusy(inviteId: invite.inviteId, kind: .accept),
                            isDeclineBusy: pendingTripsViewModel.isBusy(inviteId: invite.inviteId, kind: .decline),
                            isCancelBusy: false,
                            isDisabled: pendingTripsViewModel.isInviteDisabled(invite.inviteId),
                            onAccept: { pendingTripsViewModel.accept(invite: invite) },
                            onDecline: { pendingTripsViewModel.decline(invite: invite) },
                            onCancel: nil
                        )
                        .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                        .listRowBackground(Color.clear)
                    }
                }
            } header: {
                Text("Pending Invites".localized)
            }
            .textCase(nil)
            .listRowBackground(Color.clear)
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
        .alert("Error".localized, isPresented: Binding(
            get: { pendingTripsViewModel.errorMessage != nil },
            set: { if !$0 { pendingTripsViewModel.errorMessage = nil } }
        )) {
            Button("OK".localized, role: .cancel) {
                pendingTripsViewModel.errorMessage = nil
            }
        } message: {
            Text(pendingTripsViewModel.errorMessage ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RoadTrip Royale".localized)
                .font(.system(.largeTitle, design: .rounded))
                .fontWeight(.bold)
                .foregroundStyle(Color.Theme.primaryBlue)
                .shadow(color: Color.Theme.primaryBlue.opacity(0.5), radius: 5)
            
            Text("Spot license plates, conquer the map, and rule the open road!".localized)
                .font(.system(.title2, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(Color.Theme.primaryBlue.opacity(0.8))

            Text("Track every plate you see across the United States, Canada, and Mexico.".localized)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
        }
    }

    private var activeTripEmptyCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "car.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.Theme.accentYellow)

            Text("No trips yet".localized)
                .font(.system(.title3, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(Color.Theme.primaryBlue)

            Text("Start your first adventure and begin collecting plates from across North America.".localized)
                .multilineTextAlignment(.center)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
                .padding(.horizontal)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.Theme.cardBackground)
                .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
        )
        .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No active trips. Time you get on the open road.".localized)
    }

    @ViewBuilder
    private var activeTripsPendingLeaveFooter: some View {
        if let hint = activeTripsListViewModel.pendingLeaveSyncHint {
            Text(hint)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Color.secondary)
                .padding(.top, 4)
                .accessibilityLabel(hint)
        }
    }

    private var pendingInvitesEmptyCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "envelope.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.Theme.accentYellow)

            Text("No pending invites".localized)
                .font(.system(.title3, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(Color.Theme.primaryBlue)
            
            Text("When someone invites you to a trip, it will appear here.".localized)
                .multilineTextAlignment(.center)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
                .padding(.horizontal)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.Theme.cardBackground)
                .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
        )
        .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No pending invites. When someone invites you to a trip, it will appear here.".localized)
    }

    private var activeSessionList: some View {
        ForEach(activeTripsListViewModel.items) { item in
            let pendingOutgoingInviteCount = outgoingPendingInviteCount(for: item.session.id)
            Button {
                FeedbackService.shared.buttonTap()
                mainCoordinator.openSession(item.session.id)
            } label: {
                TripSessionRow(
                    session: item.session,
                    rollup: item.rollup,
                    pendingOutgoingInviteCount: pendingOutgoingInviteCount
                )
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .listRowInsets(.init(top: 6, leading: 20, bottom: 6, trailing: 20))
            .listRowBackground(Color.clear)
            .accessibilityLabel(activeTripAccessibilityLabel(for: item.session, pendingOutgoingInviteCount: pendingOutgoingInviteCount))
            .accessibilityHint("Double tap to open trip".localized)
        }
        .onDelete { offsets in
            FeedbackService.shared.buttonTap()
            activeTripsListViewModel.deleteSessions(at: offsets, userId: authService.currentUser?.firebaseUID ?? authService.currentUser?.id)
            if activeTripsListViewModel.errorMessage == nil {
                FeedbackService.shared.actionSuccess()
            } else {
                FeedbackService.shared.actionError()
            }
        }
    }

    private func outgoingPendingInviteCount(for sessionId: UUID) -> Int {
        pendingTripsViewModel.outgoingInvites.filter { invite in
            UUID(uuidString: invite.tripSessionId) == sessionId
                && (invite.statusEnum == .pending || invite.statusEnum == .sent)
        }.count
    }

    private func activeTripAccessibilityLabel(for session: TripSession, pendingOutgoingInviteCount: Int) -> String {
        guard pendingOutgoingInviteCount > 0 else {
            return "Trip: %@".localized(session.name)
        }
        let pendingLine = pendingOutgoingInviteCount == 1
            ? "1 outgoing invite pending".localized
            : "%d outgoing invites pending".localized(pendingOutgoingInviteCount)
        return ["Trip: %@".localized(session.name), pendingLine].joined(separator: ". ")
    }

    private var addTripButton: some View {
        Button {
            FeedbackService.shared.buttonTap()
            isShowingCreateSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24, weight: .bold))
                    .accessibilityHidden(true)
                Text("Create Trip".localized)
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                Capsule()
                    .fill(Color.Theme.primaryBlue)
            )
            .foregroundStyle(Color.white)
            .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
        }
        .padding(.trailing, 20)
        .padding(.bottom, 32)
        .accessibilityLabel("Create Trip".localized)
        .accessibilityHint("Opens a sheet to create a new trip".localized)
        .accessibilityAddTraits(.isButton)
    }
}

private struct PendingInviteCard: View {
    let invite: TripInvite
    let snapshot: InviteDisplaySnapshot
    let isIncoming: Bool
    let isAcceptBusy: Bool
    let isDeclineBusy: Bool
    let isCancelBusy: Bool
    let isDisabled: Bool
    let onAccept: (() -> Void)?
    let onDecline: (() -> Void)?
    let onCancel: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(invite.tripName)
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                Spacer()
                Text(invite.statusEnum.rawValue.capitalized)
                    .font(.system(.footnote, design: .rounded))
                    .fontWeight(.medium)
                    .foregroundStyle(statusColor)
            }

            Divider()
                .background(Color.Theme.softBrown.opacity(0.2))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Label(snapshot.counterpartyLine, systemImage: "person")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                if let games = snapshot.gamesOnTripLine {
                    Text(games)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                }
            }

            if isIncoming, invite.statusEnum == .pending {
                HStack(spacing: 12) {
                    Button {
                        FeedbackService.shared.buttonTap()
                        onAccept?()
                    } label: {
                        InviteActionLabel(
                            title: "Accept".localized,
                            isBusy: isAcceptBusy,
                            busyKind: .accept
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.Theme.primaryBlue)
                    .disabled(isDisabled)
                    .accessibleButton(
                        label: isAcceptBusy
                            ? InviteBusyKind.accept.localizedBusyTitle
                            : "Accept invite".localized,
                        hint: "Accepts this trip invite".localized
                    )
                    Button {
                        FeedbackService.shared.buttonTap()
                        onDecline?()
                    } label: {
                        InviteActionLabel(
                            title: "Decline".localized,
                            isBusy: isDeclineBusy,
                            busyKind: .decline
                        )
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .disabled(isDisabled)
                    .accessibleButton(
                        label: isDeclineBusy
                            ? InviteBusyKind.decline.localizedBusyTitle
                            : "Decline invite".localized,
                        hint: "Declines this trip invite".localized
                    )
                }
            } else if !isIncoming, let onCancel = onCancel {
                Button {
                    FeedbackService.shared.buttonTap()
                    onCancel()
                } label: {
                    InviteActionLabel(
                        title: "Cancel Invite".localized,
                        isBusy: isCancelBusy,
                        busyKind: .cancel
                    )
                }
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
                .disabled(isDisabled)
                .accessibleButton(
                    label: isCancelBusy
                        ? InviteBusyKind.cancel.localizedBusyTitle
                        : "Cancel invite".localized,
                    hint: "Cancels this outgoing invite".localized
                )
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.Theme.cardBackground)
                .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
        )
        .accessibilityElement(children: .combine)
    }

    private var statusColor: Color {
        switch invite.statusEnum {
        case .pending, .sent: return Color.Theme.accentYellow
        case .accepted: return .green
        case .declined, .canceled, .expired: return Color.Theme.softBrown
        }
    }
}

// App Preferences enums are now in Core/AppPreferences.swift

// Default Settings View for new trips
struct DefaultSettingsView: View {
    @StateObject private var coordinator = MainSettingsCoordinator()
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var systemColorScheme
    
    // App Preferences
    @AppStorage("appDarkMode") private var appDarkModeRaw: String = AppDarkMode.system.rawValue
    
    // Use @State to explicitly track color scheme and ensure view updates
    @State private var currentColorScheme: ColorScheme?
    
    // Computed property to determine color scheme from preference
    private func updateColorScheme() {
      print("Current: \(appDarkModeRaw)--System: \(systemColorScheme)")
        let darkMode = AppDarkMode(rawValue: appDarkModeRaw) ?? .system
        switch darkMode {
        case .light:
            currentColorScheme = .light
        case .dark:
            currentColorScheme = .dark
        case .system:
            // When system, use the actual system color scheme
            currentColorScheme = systemColorScheme
        }
    }
    // TODO(cloud-prefs): re-enable when wired — no production distance formatting consumer.
    // @AppStorage("appDistanceUnit") private var appDistanceUnitRaw: String = AppDistanceUnit.miles.rawValue
    @AppStorage("appMapStyle") private var appMapStyleRaw: String = AppMapStyle.standard.rawValue
    // TODO(cloud-prefs): re-enable when wired — String.localized does not apply this override.
    // @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.english.rawValue
    @AppStorage("appPlaySoundEffects") private var appPlaySoundEffects = true
    @AppStorage("appUseVibrations") private var appUseVibrations = true

    #if DEBUG
    @AppStorage("DebugForcePersistenceSave") private var forceFailureOnSave = false
    @AppStorage("DebugForcePersistenceCreate") private var forceFailureOnCreate = false
    @AppStorage("DebugForcePersistenceAppend") private var forceFailureOnAppend = false
    #endif

    @EnvironmentObject var authService: FirebaseAuthService
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var socialInboxBadges = SocialInboxBadgeService.shared
    
    // Computed properties for picker bindings
    private var appDarkMode: Binding<AppDarkMode> {
        Binding(
            get: { AppDarkMode(rawValue: appDarkModeRaw) ?? .system },
            set: { appDarkModeRaw = $0.rawValue }
        )
    }
    
    // TODO(cloud-prefs): re-enable when wired — no production distance formatting consumer.
    // private var appDistanceUnit: Binding<AppDistanceUnit> {
    //     Binding(
    //         get: { AppDistanceUnit(rawValue: appDistanceUnitRaw) ?? .miles },
    //         set: { appDistanceUnitRaw = $0.rawValue }
    //     )
    // }
    
    private var appMapStyle: Binding<AppMapStyle> {
        Binding(
            get: { AppMapStyle(rawValue: appMapStyleRaw) ?? .standard },
            set: { appMapStyleRaw = $0.rawValue }
        )
    }
    
    // TODO(cloud-prefs): re-enable when wired — String.localized does not apply this override.
    // private var appLanguage: Binding<AppLanguage> {
    //     Binding(
    //         get: { AppLanguage(rawValue: appLanguageRaw) ?? .english },
    //         set: { appLanguageRaw = $0.rawValue }
    //     )
    // }
    
    var body: some View {
      NavigationStack(path: $coordinator.path) { //NavigationStack(path: Binding(get: { coordinator.path }, set: { coordinator.path = $0 })) {
            AppBackgroundView {
                List {
                    Section {
                        VStack(spacing: 12) {
                            // Profile (from User section, but no section header)
                            if authService.currentUser != nil {
                                SettingNavigationRow(
                                    title: "Profile".localized,
                                    description: "Edit username and manage account".localized,
                                    icon: "person.circle"
                                ) {
                                    coordinator.navigateToProfile()
                                }

                                Divider()
                            }

                            SettingNavigationRow(
                                title: "Friends".localized,
                                description: "Manage your friends and friend requests".localized,
                                icon: "person.2",
                                badgeCount: socialInboxBadges.pendingFriendRequestsCount
                            ) {
                                coordinator.navigateToFriends()
                            }

                            Divider()

                            SettingNavigationRow(
                                title: "Family".localized,
                                description: "View and manage your family".localized,
                                icon: "house",
                                badgeCount: socialInboxBadges.pendingFamilyInboxCount
                            ) {
                                coordinator.navigateToFamily()
                            }

                            Divider()

                            // Privacy & Permissions
                            SettingNavigationRow(
                                title: "Privacy & Permissions".localized,
                                description: "Manage location, microphone, notifications, and other permissions".localized,
                                icon: "hand.raised.fill"
                            ) {
                                coordinator.navigateToPrivacyPermissions()
                            }
                            
                            Divider()
                            
                            // App Preferences
                            SettingNavigationRow(
                                title: "App Preferences".localized,
                                description: "Customize dark mode, map style, and other app settings",
                                icon: "slider.horizontal.3"
                            ) {
                                coordinator.navigateToAppPreferences()
                            }
                            
                            Divider()
                            
                            // New Trip/Game Defaults
                            SettingNavigationRow(
                                title: "New Trip/Game Defaults".localized,
                                description: "Set default countries, tracking, and voice settings for new trips and games".localized,
                                icon: "plus.circle.fill"
                            ) {
                                coordinator.navigateToNewTripDefaults()
                            }
                            
                            Divider()
                            
                          if false {
                            // Voice Defaults
                            SettingNavigationRow(
                              title: "Voice Defaults",
                              description: "Configure default voice recognition settings for new trips",
                              icon: "mic.fill"
                            ) {
                              coordinator.navigateToVoiceDefaults()
                            }
                            
                            Divider()
                            
                          }
                            
                            // Help & About
                            SettingNavigationRow(
                                title: "Help & About".localized,
                                description: "Get help, report bugs, suggest features, and learn about the app".localized,
                                icon: "questionmark.circle.fill"
                            ) {
                                coordinator.navigateToHelpAbout()
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .background(Color.Theme.cardBackground)
                        .cornerRadius(20)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                        .listRowBackground(Color.clear)
                    }
                    .textCase(nil)

                    #if DEBUG
                    Section {
                        Toggle(isOn: $forceFailureOnSave) {
                            Text("Force failure on save".localized)
                        }
                        .accessibilityLabel("Force failure on save".localized)
                        .accessibilityHint("Next session save will fail (settings save, start/end/reset/delete trip)")

                        Toggle(isOn: $forceFailureOnCreate) {
                            Text("Force failure on create".localized)
                        }
                        .accessibilityLabel("Force failure on create".localized)
                        .accessibilityHint("Next session create will fail (create trip)")

                        Toggle(isOn: $forceFailureOnAppend) {
                            Text("Force failure on append".localized)
                        }
                        .accessibilityLabel("Force failure on append".localized)
                        .accessibilityHint("Next event append will fail (mark found, unfind, lifecycle events)")
                    } header: {
                        Text("Debug – Force persistence failures".localized)
                    }
                    .listRowBackground(Color.Theme.cardBackground)
                    .accessibilityElement(children: .contain)
                    #endif
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done".localized) {
                        dismiss()
                    }
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                }
            }
            .preferredColorScheme(currentColorScheme)
            .onAppear {
                updateColorScheme()
            }
            .onChange(of: appDarkModeRaw) { oldValue, newValue in
                updateColorScheme()
            }
            .onChange(of: systemColorScheme) { oldValue, newValue in
                // Update if we're using system mode
                let darkMode = AppDarkMode(rawValue: appDarkModeRaw) ?? .system
                if darkMode == .system {
                    currentColorScheme = newValue
                }
            }
            .navigationDestination(for: MainSettingsCoordinator.SettingsDestination.self) { destination in
                Group {
                    switch destination {
                    case .profile:
                        if let user = authService.currentUser {
                            UserProfileView(user: user, authService: authService)
                        } else {
                            // Fallback view if no user (shouldn't happen since button is hidden)
                            Text("No user available")
                                .foregroundStyle(Color.Theme.softBrown)
                        }
                    case .privacyPermissions:
                        PrivacyPermissionsView()
                    case .appPreferences:
                        AppPreferencesView()
                    case .newTripDefaults:
                        NewTripDefaultsView()
                    case .voiceDefaults:
                        VoiceDefaultsView()
                    case .helpAbout:
                        HelpAboutView()
                    case .friends:
                        RegisteredAccountGate(feature: .friends) {
                            FriendsHub()
                                .environmentObject(authService)
                        }
                        .environmentObject(authService)
                    case .family:
                        RegisteredAccountGate(feature: .family) {
                            FamilyDashboard()
                                .environmentObject(authService)
                        }
                        .environmentObject(authService)
                    case .achievements:
                        if let user = authService.currentUser {
                            AchievementListView(user: user)
                        } else {
                            Text("No user available")
                                .foregroundStyle(Color.Theme.softBrown)
                        }
                    case .rankProgression:
                        if let user = authService.currentUser {
                            RankProgressionView(user: user)
                        } else {
                            Text("No user available")
                                .foregroundStyle(Color.Theme.softBrown)
                        }
//                    case .deferredProfileSetup:
//                        DeferredProfileSetupHubView()
//                            .environmentObject(authService)
                    }
                }
            }
        }
      .environmentObject(coordinator)
    }
    
    // Removed: All settings content moved to separate view files
    // - PrivacyPermissionsView
    // - AppPreferencesView
    // - NewTripDefaultsView (New Trip/Game Defaults)
    // - VoiceDefaultsView
    // - HelpAboutView
}

#Preview {
    ContentView(appCoordinator: AppCoordinator())
        .environmentObject(FirebaseAuthService())
        .modelContainer(for: [TripSessionEntity.self, GameInstanceEntity.self, TripActivityEventEntity.self], inMemory: true)
}

/// Step 05 — Preview for persistence error state (same copy as alert message for design/accessibility).
#Preview("Persistence error state") {
    VStack(spacing: 16) {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.largeTitle)
            .foregroundStyle(.orange)
        Text("Error".localized)
            .font(.headline)
        Text("Couldn't save. Please try again.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }
    .padding()
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Error".localized)
    .accessibilityHint("Couldn't save. Please try again.")
}

// MARK: - Permission Row Component

private struct PermissionRow: View {
    let title: String
    let icon: String
    let status: String
    let statusColor: Color
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                }
                
                Spacer()
                
                Text(status)
                    .font(.system(.caption, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(statusColor)
              
            if statusColor != .green {
              Image(systemName: "arrow.up.right.square")
                  .font(.system(size: 12))
                  .foregroundStyle(Color.Theme.primaryBlue)
            }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.Theme.cardBackground)
            )
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
    }
}
