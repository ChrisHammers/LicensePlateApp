//
//  LicensePlateGameView.swift
//  LicensePlateApp
//
//  Step 6.8 — License plate game screen (direct copy from TripTrackerView). Trip container is TripSessionView.
//

import SwiftUI
import Speech
import AudioToolbox
import MapKit
import CoreLocation
import GoogleMaps
import Combine

/// License plate gameplay: map, list, voice, discoveries. Reached from TripSessionView when user taps the license plate game.
struct LicensePlateGameView: View {
    enum Tab: CaseIterable, Identifiable {
        case list
        case voice
        #if DEBUG
        case progression
        #endif
        
        var id: Self { self }

        var title: String {
            switch self {
            case .list: return "List".localized
            case .voice: return "Voice".localized
            #if DEBUG
            case .progression: return "Progress".localized
            #endif
            }
        }

        var systemImage: String {
            switch self {
            case .list: return "list.bullet"
            case .voice: return "person.wave.2.fill"
            #if DEBUG
            case .progression: return "chart.bar.doc.horizontal"
                #endif
            }
        }
    }

    let authService: FirebaseAuthService

    @StateObject private var viewModel: LicensePlateGameViewModel
    @EnvironmentObject var riskAssessment: RiskAssessmentService
    @StateObject private var speechRecognizer = SpeechRecognizer(onListeningStarted: {
        FeedbackService.shared.startRecording()
    })
    @ObservedObject private var locationManager = LocationManager.shared
    
    // App Preferences for feedback
    @AppStorage("appPlaySoundEffects") private var appPlaySoundEffects = true
    @AppStorage("appUseVibrations") private var appUseVibrations = true
    @AppStorage(FirstSessionStateKeys.hasLoggedFirstFind) private var hasLoggedFirstFind = false

    @State private var selectedTab: Tab = .list
    @State private var lastMatchedRegion: PlateRegion?
    @State private var showVoiceMatchConfirmation = false
    @State private var lastProcessedText: String = ""
    @State private var showSettings = false
    @State private var visibleCountry: PlateRegion.Country = .unitedStates
    @State private var showFullScreenMap = false
    @State private var showEndGameConfirmation = false
    @State private var chipWidth: CGFloat = 0
    @State private var chipHeight: CGFloat = 0
    @State private var micListeningPulseScale: CGFloat = 1.0
    @State private var showRiskAdvisoryMessage = false
    @State private var pendingRemovalRegionID: String?
    @State private var showRemoveFindConfirmation = false
    @State private var riskPresentationStyle: RiskPresentationStyle? = nil
    @State private var retryAction: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var competitiveDisplayNames: [String: String] = [:]
    @ObservedObject private var userProgression = UserProgressionService.shared
    @ObservedObject private var userProgressionRepository = UserProgressionRepository.shared
    @State private var progressionScoringNames: [String: String] = [:]

    @State private var cameraPosition: GMSCameraPosition = {
        // Initialize with default US position, will be updated on appear
        let center = CLLocationCoordinate2D(latitude: 40.8283, longitude: -106.5795)
        return GMSCameraPosition.from(coordinate: center, zoom: 4.0)
    }()
    @Namespace private var mapNamespace

    init(session: TripSession, game: GameInstance, authService: FirebaseAuthService) {
        self.authService = authService
        _viewModel = StateObject(wrappedValue: LicensePlateGameViewModel(
            session: session,
            game: game,
            tripSessionRepository: TripSessionRepository.shared,
            gameInstanceRepository: GameInstanceRepository.shared,
            tripActivityEventRepository: TripActivityEventRepository.shared,
            lifecycleService: TripSessionLifecycleService.shared,
            authService: authService
        ))
    }

    var body: some View {
        AppBackgroundView {
            VStack(spacing: 0) {
                header

                // Keep both views in hierarchy to preserve scroll position
                ZStack {
                    ZStack(alignment: .bottom) {
                        regionList
                            .opacity(selectedTab == .list ? 1 : 0)
                            .allowsHitTesting(selectedTab == .list)

                        if !hasLoggedFirstFind && selectedTab == .list && viewModel.isGamePlayActive {
                            FirstFindCoachMarkOverlay()
                                .padding(.horizontal, 20)
                                .padding(.bottom, 12)
                                .allowsHitTesting(false)
                        }
                    }

                    voiceCaptureView
                        .opacity(selectedTab == .voice ? 1 : 0)
                        .allowsHitTesting(selectedTab == .voice)
                    #if DEBUG
                    gameProgressionTab
                        .opacity(selectedTab == .progression ? 1 : 0)
                        .allowsHitTesting(selectedTab == .progression)
                    #endif
                }

                customTabBar
            }
        }
        .ignoresSafeArea(.all, edges: .bottom)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(gameDisplayName)
        .toolbar {
            if !showFullScreenMap {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(gameDisplayName)
                            .font(.headline)
                            .lineLimit(1)

                        Text(viewModel.currentSession.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                       // FeedbackService.shared.buttonTap()
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundStyle(Color.Theme.primaryBlue)
                    }
                    .accessibilityLabel("Game settings".localized)
                    .accessibilityHint("Opens settings for this license plate game: scope, voice, and game actions".localized)
                }
            }
        }
        .toolbar(showFullScreenMap ? .hidden : .visible, for: .navigationBar)
        .sheet(isPresented: $showSettings) {
            GameSettingsView(viewModel: viewModel, onGameInstanceRemoved: {
                dismiss()
            })
                .environmentObject(authService)
        }
        .alert("Error".localized, isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.clearError(); retryAction = nil } }
        )) {
            Button("OK".localized, role: .cancel) {
                viewModel.clearError()
                retryAction = nil
            }
            Button("Retry".localized) {
                AnalyticsService.shared.log(.persistenceRetryTapped(context: "trip_tracker_save"))
                retryAction?()
                viewModel.clearError()
                retryAction = nil
            }
        } message: {
            if let msg = viewModel.errorMessage {
                Text(msg)
            }
        }
        .alert("Remove this find?".localized, isPresented: $showRemoveFindConfirmation) {
            Button("Cancel".localized, role: .cancel) {
                pendingRemovalRegionID = nil
            }
            Button("Remove".localized, role: .destructive) {
                guard let regionID = pendingRemovalRegionID else { return }
                pendingRemovalRegionID = nil
                guard viewModel.removeDiscovery(regionID: regionID) else { return }
                withAccessibleAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {}
                let result = riskAssessment.assessAfterDiscoveryChange(
                    tripId: viewModel.sessionId,
                    gameInstanceId: viewModel.game.id,
                    foundRegions: viewModel.foundRegions,
                    lastChange: (regionID, false, Date())
                )
                applyRiskPresentation(result.flags)
            }
        } message: {
            Text("By removing the current find, you lose your discovery and game points.".localized)
        }
        // Step 11: Unusual Activity modal suppressed (risk still logged to analytics). Non-blocking options: toast/banner, inline hint, or settings summary.
        // .alert("Unusual Activity".localized, isPresented: $showRiskAdvisoryMessage) {
        //     Button("OK".localized, role: .cancel) {}
        // } message: {
        //     Text("Unusual activity was detected; this is only for your awareness.".localized)
        // }
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                rejectedInvalidParticipantBanner
                rejectedDuplicateBanner
                // blockedRetapBanner — same-item retap hint disabled; removal confirmation alert remains (Step 16.4).
                fairnessToastBanner
                riskAdvisoryBanner
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.fairnessToasts.count)
        }
        .onAppear {
            FeedbackService.shared.updatePreferences(hapticEnabled: appUseVibrations, soundEnabled: appPlaySoundEffects)
        }
        .onChange(of: appUseVibrations) { _, newValue in
            FeedbackService.shared.updatePreferences(hapticEnabled: newValue, soundEnabled: appPlaySoundEffects)
        }
        .onChange(of: appPlaySoundEffects) { _, newValue in
            FeedbackService.shared.updatePreferences(hapticEnabled: appUseVibrations, soundEnabled: newValue)
        }
        .overlay {
            if showFullScreenMap {
                FullScreenMapView(
                    tripSessionId: viewModel.sessionId,
                    enabledCountries: gameScopedEnabledCountries,
                    enabledRegionIds: gameScopedTargetRegionIds,
                    foundRegionIDs: viewModel.displayFoundRegionIDsForMap,
                    foundRegions: viewModel.foundRegions,
                    finderIdentities: viewModel.finderIdentitiesByUserId,
                    cameraPosition: $cameraPosition,
                    locationManager: locationManager,
                    namespace: mapNamespace,
                    isPresented: $showFullScreenMap
                )
                .accessibleTransition(.opacity)
                .zIndex(1000)
            }
        }
        .onAppear {
            viewModel.refreshSession()
            viewModel.refreshGame()
            viewModel.refreshFoundRegions()
            Task { await viewModel.refreshFairnessUiAfterNavigationOrReconnect() }
            // Request location permission when view appears
            if locationManager.authorizationStatus == .notDetermined {
                locationManager.requestAuthorization()
            }
            // Switch to list tab if the game is not playable and we're on voice tab
            if !viewModel.isGamePlayActive && selectedTab == .voice {
                selectedTab = .list
            }
            
            // Initialize camera position based on game-scoped enabled countries (only once on appear)
            let countries = gameScopedEnabledCountries
            let center: CLLocationCoordinate2D
            let zoom: Float

            if countries.contains(.unitedStates) && countries.contains(.canada) && countries.contains(.mexico) {
                center = CLLocationCoordinate2D(latitude: 45.0, longitude: -100.0)
                zoom = 3.5
            } else if countries.contains(.unitedStates) && countries.contains(.canada) {
                center = CLLocationCoordinate2D(latitude: 50.0, longitude: -100.0)
                zoom = 3.8
            } else if countries.contains(.unitedStates) && countries.contains(.mexico) {
                center = CLLocationCoordinate2D(latitude: 32.0, longitude: -100.0)
                zoom = 4.0
            } else if countries.contains(.unitedStates) {
                center = CLLocationCoordinate2D(latitude: 40.8283, longitude: -106.5795)
                zoom = 4.0
            } else if countries.contains(.canada) {
                center = CLLocationCoordinate2D(latitude: 56.1304, longitude: -106.3468)
                zoom = 4.5
            } else if countries.contains(.mexico) {
                center = CLLocationCoordinate2D(latitude: 23.6345, longitude: -102.5528)
                zoom = 5.5
            } else {
                center = CLLocationCoordinate2D(latitude: 40.8283, longitude: -106.5795)
                zoom = 4.0
            }
            
            cameraPosition = GMSCameraPosition.from(coordinate: center, zoom: zoom)
        }
        .task {
            // Periodic location-cache warm while this screen is front-most, so find-time
            // capture stays inside the freshness window even with route tracking off.
            // Each tick is a no-op unless save-location is on, nothing else feeds the
            // cache, and the fix has aged out. Cancels automatically on disappear.
            while !Task.isCancelled {
                viewModel.warmDiscoveryLocationCacheIfNeeded()
                try? await Task.sleep(for: .seconds(LicensePlateGameViewModel.locationWarmInterval))
            }
        }
        .onChange(of: viewModel.currentSession.startedAt) { _, _ in
            if !viewModel.isGamePlayActive && selectedTab == .voice {
                selectedTab = .list
            }
        }
        .onChange(of: viewModel.currentSession.status) { _, newValue in
            if (newValue == .ended || newValue == .cancelled), selectedTab == .voice {
                selectedTab = .list
            }
        }
        .onChange(of: viewModel.game.commonConfig.lifecycleState) { _, _ in
            if !viewModel.isGamePlayActive && selectedTab == .voice {
                selectedTab = .list
            }
        }
        .onChange(of: showFullScreenMap) { oldValue, newValue in
            // When closing full screen map, reset camera to current visible country
            if oldValue == true && newValue == false {
                let (center, zoom) = calculateCameraPositionForCountry(visibleCountry)
                withAccessibleAnimation(.easeInOut(duration: 0.5)) {
                    cameraPosition = GMSCameraPosition.from(coordinate: center, zoom: zoom)
                }
            }
        }
        .onChange(of: selectedTab) { oldValue, newValue in
            if newValue == .voice {
                Task {
                    await requestSpeechAuthorizationIfNeeded()
                }
            } else {
                speechRecognizer.stopListening()
            }
        }
        .onChange(of: speechRecognizer.isListening) { oldValue, newValue in
            if oldValue == true && newValue == false {
                micListeningPulseScale = 1.0
                // When listening stops, process the final recognized text
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    processRecognizedText(speechRecognizer.recognizedText)
                }
            }
        }
        // TODO: Fix 2 (trip re-entry) — Add .onDisappear { speechRecognizer.stopListening() } here. See .cursor/plans/TRIP_REENTRY_FIXES_TODO_AND_DONE.md
        .overlay {
            if showVoiceMatchConfirmation, let region = lastMatchedRegion {
                VoiceConfirmationDialog(
                    region: region,
                    onAdd: {
                      confirmAddRegion(region, usingTab: .voice)
                    },
                    onCancel: {
                        showVoiceMatchConfirmation = false
                        lastMatchedRegion = nil
                    },
                    skipConfirmation: Binding(
                        get: { viewModel.skipVoiceConfirmation },
                        set: { viewModel.updateSkipVoiceConfirmation($0) }
                    )
                )
            }
        }
    }

    private var gameDisplayName: String {
        GameType(rawValue: viewModel.game.definitionId)?.displayName ?? viewModel.game.definitionId
    }

    /// Game-scoped enabled countries (and regions) for board/progress. Uses game's license-plate config when available; else North America default.
    private var gameLicensePlateConfig: LicensePlateGameConfig {
        viewModel.game.licensePlateConfig() ?? LicensePlateGameConfig(
            selectedCountriesRawValues: [
                PlateRegion.Country.unitedStates.rawValue,
                PlateRegion.Country.canada.rawValue,
                PlateRegion.Country.mexico.rawValue
            ],
            territoryOptions: LicensePlateTerritoryOptions()
        )
    }

    private var gameScopedTargetRegionIds: Set<String> {
        LicensePlateScopeCalculator.targetRegionIdSet(for: gameLicensePlateConfig)
    }

    private var gameScopedEnabledCountries: [PlateRegion.Country] {
        let targetIds = gameScopedTargetRegionIds
        return Array(Set(PlateRegion.all.filter { targetIds.contains($0.id) }.map(\.country)))
    }

    private var headerFoundValue: String {
        "\(viewModel.displayFoundCountForHeader)"
    }

    /// Remaining count: game-scoped completion goal when license-plate; else target ID count.
    private var headerRemainingValue: String {
        let foundCount = viewModel.displayFoundCountForHeader
        if viewModel.game.licensePlateConfig() != nil {
            let goal = LicensePlateScopeCalculator.completionGoal(for: gameLicensePlateConfig)
            return "\(max(0, goal - foundCount))"
        }
        return "\(max(0, gameScopedTargetRegionIds.count - foundCount))"
    }

    private var currentUserId: String {
        authService.currentUser?.firebaseUID ?? authService.currentUser?.id ?? ""
    }

    private var header: some View {
        VStack(spacing: 16) {
//            Text(currentSession.name)
//                .font(.system(.title2, design: .rounded))
//                .fontWeight(.bold)
//                .foregroundStyle(Color.Theme.primaryBlue)

          // Map view (game-scoped)
          RegionMapView(
              tripSessionId: viewModel.sessionId,
              enabledCountries: gameScopedEnabledCountries,
              enabledRegionIds: gameScopedTargetRegionIds,
              foundRegionIDs: viewModel.displayFoundRegionIDsForMap,
              foundRegions: viewModel.foundRegions,
              visibleCountry: visibleCountry,
              cameraPosition: $cameraPosition,
              namespace: mapNamespace,
              showFullScreen: $showFullScreenMap,
              locationManager: locationManager
          )
          .frame(height: 150)
          .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
          .padding(.horizontal, 32)
          
            HStack(spacing: 24) {
                summaryChip(title: "Found".localized, value: headerFoundValue, measuredWidth: $chipWidth, measuredHeight: $chipHeight)
                startEndGameButton(height: chipHeight)
                summaryChip(title: "Remaining".localized, value: headerRemainingValue, measuredWidth: $chipWidth, measuredHeight: $chipHeight)
            }
            .padding(.horizontal, 32)

            if viewModel.game.commonConfig.gameMode == .competitive {
                competitivePlaySections
            }
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.Theme.cardBackground)
                .padding(.horizontal, 12)
        )
        .padding(.top, 6)
        .padding(.bottom, 6)
    }

    @State private var competitivePlaySectionsContentSize: CGSize = .zero
    
    private var competitivePlaySections: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Standings".localized)
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(Color.Theme.primaryBlue)
                .accessibilityAddTraits(.isHeader)
            ScrollView {
               // VStack(spacing: 8) {
                    ForEach(viewModel.competitiveStandings) { row in
                        let c = row.contribution
                        HStack(alignment: .firstTextBaseline, spacing: 18) {
                            Text("Rank #%d".localized(row.rank))
                                .font(.system(.caption, design: .rounded))
                                .fontWeight(.medium)
                                .foregroundStyle(Color.Theme.primaryBlue)
                                .frame(minWidth: 52, alignment: .leading)
                            if row.isTiedOnScore {
                                Text("Tied".localized)
                                    .font(.system(.caption2, design: .rounded))
                                    .foregroundStyle(Color.Theme.softBrown)
                            }
                            Text(competitiveDisplayName(for: c.participantId))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(Color.Theme.primaryBlue)
                            Spacer(minLength: 4)
                            Text("%d first finds".localized(c.firstFindCount))
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(Color.Theme.softBrown)
                            Text(String(format: "%.1f", c.weightedScore))
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(Color.Theme.softBrown)
                        }
                        .padding(.bottom, 0)
                        .background(
                            GeometryReader { geo -> Color in
                                DispatchQueue.main.async {
                                    competitivePlaySectionsContentSize = geo.size
                                    print(geo.size)
                                }
                                return Color.clear
                            }
                        )
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(competitiveStandingAccessibility(row: row))
                    }
                
            }
            .frame(
                height: competitivePlaySectionsContentSize.height * 4
            )
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: competitiveStandingsTaskIdentity) {
            let ids = Set(viewModel.competitiveStandings.map(\.contribution.participantId))
            competitiveDisplayNames = await UserRepository.shared.displayNames(forUserIds: ids)
        }
    }

    private var competitiveStandingsTaskIdentity: String {
        viewModel.competitiveStandings.map { "\($0.contribution.participantId):\($0.rank):\($0.contribution.weightedScore)" }.joined(separator: "|")
    }

    private func competitiveDisplayName(for participantId: String) -> String {
        let name = competitiveDisplayNames[participantId] ?? participantId
        return ParticipantDisplayName.decorated(
            name,
            userId: participantId,
            currentUserId: currentUserId.isEmpty ? nil : currentUserId
        )
    }

    private func progressionScoringDisplayName(for participantId: String) -> String {
        let name = progressionScoringNames[participantId] ?? participantId
        return ParticipantDisplayName.decorated(
            name,
            userId: participantId,
            currentUserId: currentUserId.isEmpty ? nil : currentUserId
        )
    }

    private func competitiveStandingAccessibility(row: RankedParticipantContribution) -> String {
        let c = row.contribution
        let name = competitiveDisplayName(for: c.participantId)
        var parts = [name, "Rank #%d".localized(row.rank)]
        if row.isTiedOnScore { parts.append("Tied".localized) }
        parts.append("%d first finds".localized(c.firstFindCount))
        parts.append(String(format: "%.1f", c.weightedScore))
        return parts.joined(separator: ", ")
    }

    private func competitiveRegionDisplayName(for targetId: String) -> String {
        PlateRegion.all.first(where: { $0.id == targetId })?.name ?? targetId
    }

    private var gameScopedLedgerEvents: [XpLedgerEvent] {
        viewModel.sessionLedgerEvents.filter { $0.gameInstanceId == viewModel.game.id }
    }

    private var gameProgressionTab: some View {
        let gameLedger = gameScopedLedgerEvents
        let lastGameLedger = gameLedger.max { $0.createdAt < $1.createdAt }
        let netGameLedger = gameLedger.reduce(0) { $0 + $1.xpDelta }
        let netSessionLedger = viewModel.sessionLedgerEvents.reduce(0) { $0 + $1.xpDelta }
        let server = userProgressionRepository.snapshot
        let effective = userProgression.effectiveTotals
        // Match `UserProgressionService` math: server snapshot is treated as empty when the doc is missing.
        let serverForDelta = userProgressionRepository.snapshot ?? UserProgressionSnapshot.empty
        let globalPendingInt: Int? = effective.map { $0.totalXp - serverForDelta.totalXp }
        let p = viewModel.sessionProgressionPending
        let rankPreviewBase = server?.totalXp ?? 0
        let rankPreviewTotal = rankPreviewBase + viewModel.accountLedgerProvisionalPending
        let exportUserId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id ?? ""
        return VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    #if DEBUG
                    XpProgressionDebugExportButton(
                        userId: exportUserId,
                        sessionContext: XpProgressionDebugExporter.SessionContext(
                            sessionId: viewModel.sessionId,
                            gameInstanceId: viewModel.game.id,
                            sessionProgressionPending: p,
                            sessionLedgerNetXp: netSessionLedger,
                            gameLedgerNetXp: netGameLedger
                        )
                    )
                    Divider()
                    #endif
                    Text("game.progression.section_summary".localized)
                        .font(.headline)
                        .foregroundStyle(Color.Theme.primaryBlue)
                    progressionStatRow(
                        label: "game.progression.server_xp".localized,
                        value: {
                            if let s = server {
                                return String(s.totalXp)
                            }
                            return "game.progression.value_none".localized
                        }()
                    )
                    progressionStatRow(
                        label: "game.progression.last_server_update".localized,
                        value: server?.lastUpdatedAt.map { $0.formatted(.dateTime.month().day().hour().minute()) } ?? "game.progression.value_emdash".localized
                    )
                    Text("game.progression.account_progression_caption".localized)
                        .font(.caption2)
                        .foregroundStyle(Color.Theme.softBrown)
                    progressionStatRow(
                        label: "game.progression.account_progression_xp".localized,
                        value: {
                            if let e = effective {
                                return String(e.totalXp)
                            }
                            return "game.progression.value_unavailable".localized
                        }()
                    )
                    progressionStatRow(
                        label: "game.progression.account_rank_preview_xp".localized,
                        value: String(rankPreviewTotal)
                    )
                    Text("game.progression.account_rank_preview_caption".localized)
                        .font(.caption2)
                        .foregroundStyle(Color.Theme.softBrown)
                    progressionStatRow(
                        label: "game.progression.global_pending_xp".localized,
                        value: {
                            guard let d = globalPendingInt else { return "game.progression.value_unavailable".localized }
                            if d == 0 { return "0" }
                            return d > 0 ? "+\(d)" : "\(d)"
                        }()
                    )
                    if let e = effective, e.hasPendingLocalProgression {
                        Text("game.progression.hint_local_pending".localized)
                            .font(.caption2)
                            .foregroundStyle(Color.Theme.softBrown)
                    }
                    Divider()
                    Text("game.progression.section_local_engine".localized)
                        .font(.headline)
                        .foregroundStyle(Color.Theme.primaryBlue)
                    Text("game.progression.local_engine_trip_caption".localized)
                        .font(.caption2)
                        .foregroundStyle(Color.Theme.softBrown)
                    progressionStatRow(
                        label: "game.progression.trip_pending_xp".localized,
                        value: String(p.totalXp)
                    )
                    progressionStatRow(
                        label: "game.progression.trip_pending_finds".localized,
                        value: String(p.acceptedRegionFindCount)
                    )
                    progressionStatRow(
                        label: "game.progression.trip_pending_first_places".localized,
                        value: String(p.competitiveFirstPlaceFinishes)
                    )
                    progressionStatRow(
                        label: "game.progression.ever_competitive_first".localized,
                        value: p.everCompetitiveFirstPlace ? "game.progression.bool_yes".localized : "game.progression.bool_no".localized
                    )
                    Divider()
                    Text("game.progression.section_ledger_projection".localized)
                        .font(.headline)
                        .foregroundStyle(Color.Theme.primaryBlue)
                    Text("game.progression.local_ledger_caption".localized)
                        .font(.caption2)
                        .foregroundStyle(Color.Theme.softBrown)
                    if let bal = viewModel.localGameLedgerBalance {
                        progressionStatRow(
                            label: "game.progression.local_total_xp_game".localized,
                            value: String(bal.displayXp)
                        )
                        progressionStatRow(
                            label: "game.progression.local_provisional_xp_game".localized,
                            value: String(bal.totalXpProvisional)
                        )
                        progressionStatRow(
                            label: "game.progression.local_provisional_rows_game".localized,
                            value: String(bal.pendingAdjustmentCount)
                        )
                    } else {
                        Text("game.progression.value_unavailable".localized)
                            .font(.caption)
                            .foregroundStyle(Color.Theme.softBrown)
                    }
                    progressionStatRow(
                        label: "game.progression.local_provisional_xp_session".localized,
                        value: String(viewModel.localSessionLedgerPending.provisionalSum)
                    )
                    Divider()
                    Text("game.progression.section_ledger_summary".localized)
                        .font(.headline)
                        .foregroundStyle(Color.Theme.primaryBlue)
                    if let last = lastGameLedger {
                        progressionStatRow(
                            label: "game.progression.most_recent_delta".localized,
                            value: String(format: "%+d", last.xpDelta)
                        )
                        progressionStatRow(
                            label: "game.progression.most_recent_reason".localized,
                            value: last.reasonCode.rawValue
                        )
                    } else {
                        Text("game.progression.no_ledger_game".localized)
                            .font(.caption)
                            .foregroundStyle(Color.Theme.softBrown)
                    }
                    progressionStatRow(
                        label: "game.progression.net_ledger_xp_game".localized,
                        value: String(format: "%+d", netGameLedger)
                    )
                    progressionStatRow(
                        label: "game.progression.net_ledger_xp_session".localized,
                        value: String(format: "%+d", netSessionLedger)
                    )
                    Divider()
                    Text("game.progression.section_scoring".localized)
                        .font(.headline)
                        .foregroundStyle(Color.Theme.primaryBlue)
                    progressionStatRow(
                        label: "Game mode".localized,
                        value: viewModel.game.commonConfig.gameMode.rawValue
                    )
                    ForEach(viewModel.rankedScoringForCurrentGame) { row in
                        let c = row.contribution
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("Rank #%d".localized(row.rank))
                                Text(progressionScoringDisplayName(for: c.participantId))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Text(String(format: "%.1f", c.weightedScore))
                                    .font(.caption2)
                            }
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.Theme.primaryBlue)
                            Text("game.progression.scoring_sub".localized(
                                c.firstFindCount,
                                c.discoveryCount
                            ))
                            .font(.caption2)
                            .foregroundStyle(Color.Theme.softBrown)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("game.progression.ledger_list_title".localized)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .padding(.horizontal, 20)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(viewModel.sessionLedgerEvents.reversed())) { event in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(
                                        String(format: "%+d", event.xpDelta),
                                    )
                                    .fontWeight(.semibold)
                                    .foregroundStyle(event.xpDelta < 0 ? Color.red : Color.Theme.primaryBlue)
                                    Spacer()
                                    Text(event.status.rawValue)
                                        .font(.caption2)
                                        .foregroundStyle(Color.Theme.softBrown)
                                }
                                Text(event.itemId)
                                    .font(.caption2)
                                Text("game.progression.ledger_line_meta".localized(
                                    event.grantKind.rawValue,
                                    event.reasonCode.rawValue
                                ))
                                .font(.caption2)
                                .foregroundStyle(Color.Theme.softBrown)
                                Text("game.progression.ledger_line_ids".localized(
                                    event.id,
                                    event.sourceEventId
                                ))
                                .font(.caption2)
                                .foregroundStyle(Color.Theme.softBrown)
                                if event.gameInstanceId == viewModel.game.id {
                                    Text("game.progression.ledger_badge_game".localized)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.Theme.cardBackground, in: Capsule())
                                }
                            }
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.Theme.cardBackground)
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.Theme.background)
        .onAppear { viewModel.refreshProgressionDebugState() }
        .onChange(of: userProgression.effectiveTotals) { _, _ in
            viewModel.refreshProgressionDebugState()
        }
        .onChange(of: userProgressionRepository.snapshot) { _, _ in
            viewModel.refreshProgressionDebugState()
        }
        .task(id: viewModel.rankedScoringForCurrentGame.map { "\($0.id):\($0.contribution.weightedScore)" }.joined(separator: "|")) {
            let ids = Set(viewModel.rankedScoringForCurrentGame.map(\.contribution.participantId))
            progressionScoringNames = await UserRepository.shared.displayNames(forUserIds: ids)
        }
    }

    private func progressionStatRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color.Theme.softBrown)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Color.Theme.primaryBlue)
                .textSelection(.enabled)
        }
    }

    // PreferenceKey to measure chip size
    private struct ChipSizePreference: PreferenceKey {
        static var defaultValue: CGSize = .zero
        static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
            value = CGSize(
                width: max(value.width, nextValue().width),
                height: max(value.height, nextValue().height)
            )
        }
    }
    
    private func summaryChip(title: String, value: String, measuredWidth: Binding<CGFloat>, measuredHeight: Binding<CGFloat>) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(.title, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(Color.Theme.primaryBlue)
                .lineLimit(1)
            Text(title.uppercased())
                .font(.system(.caption, design: .rounded))
                .fontWeight(.medium)
                .foregroundStyle(Color.Theme.softBrown)
                .lineLimit(1)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .fixedSize(horizontal: true, vertical: false)
        .background(
            GeometryReader { geometry in
                Color.clear
                    .preference(key: ChipSizePreference.self, value: geometry.size)
            }
        )
        .frame(width: measuredWidth.wrappedValue > 0 ? measuredWidth.wrappedValue : nil,
               height: measuredHeight.wrappedValue > 0 ? measuredHeight.wrappedValue : nil)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.Theme.background)
        )
        .onPreferenceChange(ChipSizePreference.self) { size in
            // Update to the maximum size across all chips
            if size.width > measuredWidth.wrappedValue {
                measuredWidth.wrappedValue = size.width
            }
            if size.height > measuredHeight.wrappedValue {
                measuredHeight.wrappedValue = size.height
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
    
    private func startEndGameButton(height: CGFloat) -> some View {
        Group {
            if viewModel.currentSession.status == .ended || viewModel.currentSession.status == .cancelled {
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(.title2, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                        .accessibilityHidden(true)
                    Text(viewModel.currentSession.status == .cancelled ? "CANCELLED".localized : "ENDED".localized)
                        .font(.system(.caption, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.Theme.softBrown)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .frame(height: height > 0 ? height : nil)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.Theme.background)
                )
                .accessibilityLabel(viewModel.currentSession.status == .cancelled ? "Trip cancelled".localized : "Trip ended".localized)
                .accessibilityValue(viewModel.currentSession.status == .cancelled ? "This trip was cancelled".localized : "This trip has ended".localized)
                .accessibilityAddTraits(.isStaticText)
            } else if !viewModel.isTripContainerActive {
                VStack(spacing: 6) {
                    Image(systemName: "car.circle")
                        .font(.system(.title2, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                        .accessibilityHidden(true)
                    Text("Trip not started".localized)
                        .font(.system(.caption, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.Theme.softBrown)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity)
                .frame(height: height > 0 ? height : nil)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.Theme.background)
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Trip not started".localized)
                .accessibilityValue("Start the trip from trip settings before starting this game".localized)
                .accessibilityAddTraits(.isStaticText)
            } else if viewModel.game.commonConfig.lifecycleState == .created {
                Button {
                    FeedbackService.shared.buttonTap()
                    do {
                        try viewModel.startGame()
                    } catch {
                        viewModel.setError(error.localizedDescription)
                        retryAction = { try? viewModel.startGame() }
                    }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(.title2, design: .rounded))
                            .foregroundStyle(.white)
                            .accessibilityHidden(true)
                        Text("START".localized)
                            .font(.system(.caption, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.Theme.primaryBlue)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.isTripCreator)
                .opacity(viewModel.isTripCreator ? 1.0 : 0.5)
                .frame(height: height > 0 ? height : nil)
                .accessibilityLabel("Start Game".localized)
                .accessibilityHint(viewModel.isTripCreator ? "Starts this game so you can mark plates".localized : "Only the Driver can start the game".localized)
                .accessibilityAddTraits(.isButton)
            } else if viewModel.game.commonConfig.lifecycleState == .started {
                Button {
                    FeedbackService.shared.buttonTap()
                    showEndGameConfirmation = true
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(.title2, design: .rounded))
                            .foregroundStyle(.white)
                            .accessibilityHidden(true)
                        Text("END".localized)
                            .font(.system(.caption, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.red)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.isTripCreator)
                .opacity(viewModel.isTripCreator ? 1.0 : 0.5)
                .frame(height: height > 0 ? height : nil)
                .accessibilityLabel("End Game".localized)
                .accessibilityHint(viewModel.isTripCreator ? "Ends this game for this trip".localized : "Only the Driver can end the game".localized)
                .accessibilityAddTraits(.isButton)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(.title2, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                        .accessibilityHidden(true)
                    Text(viewModel.game.commonConfig.lifecycleState == .completed ? "DONE".localized : "GAME ENDED".localized)
                        .font(.system(.caption, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.Theme.softBrown)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .frame(height: height > 0 ? height : nil)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.Theme.background)
                )
                .accessibilityLabel(viewModel.game.commonConfig.lifecycleState == .completed ? "Game completed".localized : "Game ended".localized)
                .accessibilityAddTraits(.isStaticText)
            }
        }
        .alert("End Game".localized, isPresented: $showEndGameConfirmation) {
            Button("Cancel".localized, role: .cancel) {}
            Button("End Game".localized, role: .destructive) {
                do {
                    try viewModel.endGame()
                } catch {
                    viewModel.setError(error.localizedDescription)
                    retryAction = { try? viewModel.endGame() }
                }
            }
        } message: {
            Text("This ends this game. Make sure all participants have synced so all discoveries are counted. You can start a new game.".localized)
        }
    }

  
  private var regionListOriginal: some View {
         List {
             ForEach(PlateRegion.groupedByCountry(), id: \.country) { group in
                 Section(group.country.rawValue) {
                     ForEach(group.regions) { region in
                        RegionCellView(
                            region: region,
                            presentation: viewModel.plateRowPresentationsByRegionId[region.id],
                            isSelectedFallback: viewModel.foundRegions.contains(where: { $0.regionID == region.id }),
                            toggleAction: { toggle(regionID: region.id) }
                        )
                         .listRowBackground(Color.Theme.cardBackground)
                     }
                 }
             }
         }
         .listStyle(.insetGrouped)
         .scrollContentBackground(.hidden)
         .background(Color.Theme.background)
     }
  
    private var regionList: some View {
        // Filter regions by game-scoped target IDs (countries + territory / DC options).
        let targetIds = gameScopedTargetRegionIds
        let filteredGroups = PlateRegion.groupedByCountry().compactMap { group -> (country: PlateRegion.Country, regions: [PlateRegion])? in
            let regions = group.regions.filter { targetIds.contains($0.id) }
            guard !regions.isEmpty else { return nil }
            return (group.country, regions)
        }
        
        return List {
            ForEach(filteredGroups, id: \.country) { group in
                Section() {
                    ForEach(group.regions) { region in
                        RegionCellView(
                            region: region,
                            presentation: viewModel.plateRowPresentationsByRegionId[region.id],
                            isSelectedFallback: viewModel.foundRegions.contains(where: { $0.regionID == region.id }),
                            toggleAction: { toggle(regionID: region.id) },
                            isDisabled: !viewModel.isGamePlayActive
                        )
                        .listRowBackground(Color.Theme.cardBackground)
                        .onAppear {
                            // Update visible country when scrolling to this section
                            withAccessibleAnimation(.easeInOut(duration: 0.3)) {
                                visibleCountry = group.country
                            }
                        }
                    }
                } header: {
                    Text(group.country.rawValue.localized)
                        .font(.headline)
                        .foregroundColor(Color.Theme.primaryBlue)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.Theme.background)
                        .listRowInsets(EdgeInsets())
                        .onAppear {
                            // Update visible country when section header appears
                            withAccessibleAnimation(.easeInOut(duration: 0.3)) {
                                visibleCountry = group.country
                            }
                        }
                }
            }
        }
        .id("regionList") // Stable ID prevents list recreation and preserves scroll position
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(Color.Theme.background)
    }

  private func setFound(regionID: String, usingTab: FoundRegion.InputMethod) {
        guard viewModel.canSubmitDiscoveryTap(regionID: regionID) else {
            FeedbackService.shared.actionError()
            return
        }
        let result = viewModel.submitDiscovery(regionID: regionID, inputMethod: usingTab)
        switch result {
        case .rejectedDuplicate, .rejectedInvalidParticipant, .rejectedOutOfScope:
            FeedbackService.shared.actionError()
        case .success:
            FeedbackService.shared.actionSuccess()
            withAccessibleAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {}
            let riskResult = riskAssessment.assessAfterDiscoveryChange(
                tripId: viewModel.sessionId,
                gameInstanceId: viewModel.game.id,
                foundRegions: viewModel.foundRegions,
                lastChange: (regionID, true, Date())
            )
            applyRiskPresentation(riskResult.flags)
        case .failure(let error):
            viewModel.setError(error.localizedDescription)
            FeedbackService.shared.actionError()
        }
    }

    private func setNotFound(regionID: String, usingTab: FoundRegion.InputMethod) {
        _ = usingTab
        pendingRemovalRegionID = regionID
        showRemoveFindConfirmation = true
    }

    private func toggle(regionID: String) {
        guard viewModel.isGamePlayActive else { return }
        FeedbackService.shared.toggleRegion()
        let row = viewModel.plateRowPresentationsByRegionId[regionID]
        let isCurrentlyFound = row?.isVisuallyFound ?? viewModel.foundRegions.contains(where: { $0.regionID == regionID })
        if isCurrentlyFound {
            setNotFound(regionID: regionID, usingTab: .list)
        } else {
            setFound(regionID: regionID, usingTab: .list)
        }
    }

    @ViewBuilder private var rejectedInvalidParticipantBanner: some View {
        if let message = viewModel.rejectedInvalidParticipantMessage {
            Text(message)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.red)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .gameToastBannerShadow()
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .onTapGesture {
                    viewModel.clearRejectedInvalidParticipantMessage()
                }
                .accessibilityLabel(message)
                .accessibilityHint("Tap to dismiss".localized)
        }
    }

    @ViewBuilder private var rejectedDuplicateBanner: some View {
        if let message = viewModel.rejectedDuplicateMessage {
            Text(message)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.Theme.primaryBlue)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .gameToastBannerShadow()
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .onTapGesture {
                    viewModel.clearRejectedDuplicateMessage()
                }
                .accessibilityLabel(message)
                .accessibilityHint("Tap to dismiss".localized)
        }
    }

    // Same-item post-removal retap toast (re-enable with overlay `blockedRetapBanner` when product wants inline hint again).
     @ViewBuilder private var blockedRetapBanner: some View {
         if let message = viewModel.blockedRetapMessage {
             Text(message)
                 .font(.system(.subheadline, design: .rounded))
                 .foregroundStyle(Color.Theme.primaryBlue)
                 .padding(.horizontal, 16)
                 .padding(.vertical, 10)
                 .background(Color.Theme.cardBackground)
                 .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                 .gameToastBannerShadow()
                 .padding(.horizontal, 20)
                 .padding(.top, 8)
                 .onTapGesture {
                     viewModel.clearBlockedRetapMessage()
                 }
                 .accessibilityLabel(message)
                 .accessibilityHint("Tap to dismiss".localized)
         }
     }

    /// Vertical overlap between stacked fairness banners (oldest at top, newer peek below).
    private static let fairnessToastStackOverlap: CGFloat = 44

    @ViewBuilder private var fairnessToastBanner: some View {
        VStack(spacing: -Self.fairnessToastStackOverlap) {
            ForEach(Array(viewModel.fairnessToasts.enumerated()), id: \.element.id) { index, toast in
                fairnessToastCard(toast)
                    .zIndex(Double(viewModel.fairnessToasts.count - index))
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder private func fairnessToastCard(_ toast: FairnessToastState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(toast.title)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Color.Theme.primaryBlue)
            Text(toast.message)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.Theme.primaryBlue)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .gameToastBannerShadow()
        .padding(.horizontal, 20)
        .onTapGesture {
            viewModel.clearFairnessToast(id: toast.id)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(toast.title). \(toast.message)")
        .accessibilityHint("Tap to dismiss".localized)
    }

    /// Review-level modal is intentionally deferred; only toast and inline hint are shown for now. No hard blocking. Step 11.6.
    private func applyRiskPresentation(_ flags: [RiskFlag]) {
        let style = RiskPresentationMapper().presentation(for: flags)
        if case .none = style { return }
        if case .reviewModal = style { return }
        riskPresentationStyle = style
    }

    @ViewBuilder private var riskAdvisoryBanner: some View {
        if let style = riskPresentationStyle {
            switch style {
            case .none:
                EmptyView()
            case .toast(let messageKey), .inlineHint(let messageKey):
                Text(riskBannerMessage(for: messageKey))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .gameToastBannerShadow()
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .onTapGesture {
                        riskPresentationStyle = nil
                    }
                    .accessibilityLabel("Unusual activity".localized)
                    .accessibilityHint(riskBannerMessage(for: messageKey))
            case .reviewModal:
                EmptyView()
            }
        } else {
            EmptyView()
        }
    }

    private func riskBannerMessage(for messageKey: String) -> String {
        switch messageKey {
        case "risk.toast.notice": return "Unusual activity noticed.".localized
        case "risk.inline.warning": return "Unusual activity; for your awareness.".localized
        default: return messageKey.localized
        }
    }
    
    /// Calculate camera position for a specific country (using old Apple Maps span values)
    private func calculateCameraPositionForCountry(_ country: PlateRegion.Country) -> (CLLocationCoordinate2D, Float) {
        // Convert old MKCoordinateSpan values to Google Maps zoom levels
        // Old values from RegionMapView in the attached file:
        // US: span (50, 50) 
        // Canada: span (30, 60)
        // Mexico: span (15, 20)
        switch country {
        case .unitedStates:
            let center = CLLocationCoordinate2D(latitude: 40.8283, longitude: -106.5795)
            let span = MKCoordinateSpan(latitudeDelta: 50, longitudeDelta: 50)
            let camera = GMSCameraPosition.from(center: center, span: span)
            return (center, camera.zoom)
        case .canada:
            let center = CLLocationCoordinate2D(latitude: 56.1304, longitude: -106.3468)
            let span = MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 60)
            let camera = GMSCameraPosition.from(center: center, span: span)
            return (center, camera.zoom)
        case .mexico:
            let center = CLLocationCoordinate2D(latitude: 23.6345, longitude: -102.5528)
            let span = MKCoordinateSpan(latitudeDelta: 15, longitudeDelta: 20)
            let camera = GMSCameraPosition.from(center: center, span: span)
            return (center, camera.zoom)
        }
    }

    private var voiceCaptureView: some View {
        VStack(spacing: 32) {
            // Microphone button - push and hold
            ZStack {
                Circle()
                    .fill((speechRecognizer.isListening || speechRecognizer.isPreparing || speechRecognizer.isStarting) ? Color.Theme.primaryBlue : Color.Theme.cardBackground)
                    .frame(width: 100, height: 100)
                    .shadow(color: Color.black.opacity(0.15), radius: 15, x: 0, y: 8)
                
                Circle()
                    .stroke(speechRecognizer.isListening ? Color.Theme.accentYellow : Color.clear, lineWidth: 4)
                    .frame(width: 120, height: 120)
                    .opacity(0.6)
                    .scaleEffect(micListeningPulseScale)
                    .accessibleAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: micListeningPulseScale)
                    .onAppear { micListeningPulseScale = 1.15 }
                
                Image(systemName: (speechRecognizer.isListening || speechRecognizer.isPreparing || speechRecognizer.isStarting) ? "mic.fill" : "mic.slash.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle((speechRecognizer.isListening || speechRecognizer.isPreparing || speechRecognizer.isStarting) ? Color.white : Color.Theme.primaryBlue)
                    .accessibilityHidden(true)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if viewModel.isGamePlayActive && !speechRecognizer.isListening && !speechRecognizer.isPreparing && !speechRecognizer.isStarting && speechRecognizer.authorizationStatus == .authorized {
                            speechRecognizer.startListening()
                        }
                    }
                    .onEnded { _ in
                        if speechRecognizer.isListening || speechRecognizer.isPreparing || speechRecognizer.isStarting {
                            speechRecognizer.stopListening()
                        }
                    }
            )
            .disabled(!viewModel.isGamePlayActive || speechRecognizer.authorizationStatus != .authorized)
            .accessibilityLabel("Voice Input".localized)
            .accessibilityValue((speechRecognizer.isListening || speechRecognizer.isPreparing || speechRecognizer.isStarting) ? "Recording".localized : "Not recording".localized)
            .accessibilityHint(
                !viewModel.isGamePlayActive ? "Start the trip and this game to use voice input".localized :
                speechRecognizer.authorizationStatus != .authorized ? "Speech recognition permission required".localized :
                "Press and hold to record license plate".localized
            )
            .accessibilityAddTraits(.isButton)
            
            // Status text
            VStack(spacing: 12) {
                if speechRecognizer.authorizationStatus == .notDetermined || speechRecognizer.authorizationStatus == .denied {
                    Text("Speech Recognition Needed".localized)
                        .font(.system(.title2, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                    
                    Text("Please enable speech recognition in Settings to use voice input.".localized)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Button("Open Settings".localized) {
                        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(settingsURL)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(Color.Theme.primaryBlue)
                    )
                    .foregroundStyle(Color.white)
                    .font(.system(.headline, design: .rounded))
                } else if speechRecognizer.authorizationStatus == .authorized {
                    Text(speechRecognizer.isListening ? "Listening...".localized : (speechRecognizer.isPreparing ? "Preparing...".localized : (speechRecognizer.isStarting ? "Starting...".localized : "Hold to Talk".localized)))
                        .font(.system(.title2, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                    
                    // Always show the recognized text
                    VStack(spacing: 8) {
                        Text("Heard:".localized)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                        
                        ScrollView {
                            Text(speechRecognizer.recognizedText.isEmpty ? "No speech detected yet...".localized : speechRecognizer.recognizedText)
                                .font(.system(.body, design: .rounded))
                                .fontWeight(.medium)
                                .foregroundStyle(speechRecognizer.recognizedText.isEmpty ? Color.Theme.softBrown.opacity(0.6) : Color.Theme.primaryBlue)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .multilineTextAlignment(.leading)
                                .padding()
                        }
                        .frame(maxHeight: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.Theme.cardBackground)
                        )
                        .padding(.horizontal)
                    }
                    
                    if let errorMessage = speechRecognizer.errorMessage {
                        Text(errorMessage)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }
                } else {
                    Text("Requesting Permission...".localized)
                        .font(.system(.title2, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 12)
        .background(Color.Theme.background)
        .task {
            await requestSpeechAuthorizationIfNeeded()
        }
    }
    
    
    private func requestSpeechAuthorizationIfNeeded() async {
        if speechRecognizer.authorizationStatus == .notDetermined {
            await speechRecognizer.requestAuthorization()
        }
    }
    
    private func processRecognizedText(_ text: String) {
        // Don't process if trip is not active
        guard viewModel.isGamePlayActive else { return }
        
        let normalizedText = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else { return }
        
        // Prevent processing the same text multiple times
        if normalizedText == lastProcessedText {
            print("⏭️ [Speech Match] Skipping duplicate text: '\(normalizedText)'")
            return
        }
        lastProcessedText = normalizedText
        
        // Normalize whitespace - replace multiple spaces with single space
        let cleanedText = normalizedText.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        
        // Split text into words for better matching
        let words = cleanedText.components(separatedBy: " ").filter { !$0.isEmpty }
        
        print("🔍 [Speech Match] Processing recognized text: '\(cleanedText)'")
        print("🔍 [Speech Match] Words extracted: \(words)")
        
        // Try to find a matching region - prioritize exact matches and better matches
        var bestMatch: PlateRegion?
        var bestMatchScore = 0
        
        // Only search in game-scoped target regions (respect territory / DC options).
        let enabledRegions = PlateRegion.all.filter { gameScopedTargetRegionIds.contains($0.id) }

        for region in enabledRegions {
            let normalizedRegionName = region.name.lowercased()
            let regionWords = normalizedRegionName.components(separatedBy: " ").filter { !$0.isEmpty }
            
            // Check for exact match (highest priority)
            if cleanedText == normalizedRegionName {
                print("✅ [Speech Match] EXACT MATCH: '\(cleanedText)' == '\(normalizedRegionName)' -> \(region.name)")
                addRegionIfNotFound(region)
                return
            }
            
            // Check if the recognized text contains the full region name
            if cleanedText.contains(normalizedRegionName) {
                print("✅ [Speech Match] CONTAINS MATCH: '\(cleanedText)' contains '\(normalizedRegionName)' -> \(region.name)")
                addRegionIfNotFound(region)
                return
            }
            
            // For multi-word regions, we need stricter matching
            // Check if all words match exactly or very closely
            if regionWords.count > 1 {
                // For multi-word regions, require ALL words to match
                // Use a fresh copy of words for each region check
                var availableWords = words
                var matchedWords = 0
                var matchedWordDetails: [String] = []
                var allWordsMatched = true
                
                for regionWord in regionWords {
                    var foundMatch = false
                    var matchType = ""
                    var matchedWord: String? = nil
                    
                    // Find the first available word that matches
                    for (index, word) in availableWords.enumerated() {
                        // Exact match (preferred)
                        if word == regionWord {
                            foundMatch = true
                            matchType = "exact"
                            matchedWord = word
                            availableWords.remove(at: index)
                            break
                        }
                    }
                    
                    // If no exact match, try fuzzy matching only for very similar words
                    if !foundMatch {
                        for (index, word) in availableWords.enumerated() {
                            // Only allow fuzzy matching if words are very similar (same length or very close)
                            let lengthDiff = abs(word.count - regionWord.count)
                            if lengthDiff <= 2 && word.count >= 3 && regionWord.count >= 3 {
                                // Check if first 4 characters match (more strict than 3)
                                let wordPrefix = String(word.prefix(min(4, word.count)))
                                let regionPrefix = String(regionWord.prefix(min(4, regionWord.count)))
                                
                                if wordPrefix == regionPrefix {
                                    foundMatch = true
                                    matchType = "fuzzy-prefix"
                                    matchedWord = word
                                    availableWords.remove(at: index)
                                    break
                                }
                            }
                        }
                    }
                    
                    if foundMatch {
                        matchedWords += 1
                        matchedWordDetails.append("'\(regionWord)' (matched via \(matchType) with '\(matchedWord ?? "")')")
                    } else {
                        allWordsMatched = false
                        matchedWordDetails.append("'\(regionWord)' (NO MATCH)")
                    }
                }
                
                // Only consider it a match if ALL words matched
                if allWordsMatched && matchedWords == regionWords.count {
                    print("🔍 [Speech Match] Candidate: \(region.name) - Matched \(matchedWords)/\(regionWords.count) words")
                    print("   Details: \(matchedWordDetails.joined(separator: ", "))")
                    
                    if matchedWords > bestMatchScore {
                        bestMatch = region
                        bestMatchScore = matchedWords
                        print("   ⭐ New best match (multi-word): \(region.name) with score \(bestMatchScore)")
                    }
                } else if matchedWords > 0 {
                    print("⚠️ [Speech Match] Partial: \(region.name) - Only matched \(matchedWords)/\(regionWords.count) words")
                    print("   Details: \(matchedWordDetails.joined(separator: ", "))")
                }
            } else {
                // Single word regions - use original logic but be more strict
                let regionWord = regionWords[0]
                var foundMatch = false
                var matchType = ""
                
                let wordMatches = words.contains { word in
                    // Exact match
                    if word == regionWord {
                        foundMatch = true
                        matchType = "exact"
                        return true
                    }
                    // Fuzzy match only if very similar
                    if word.count >= 3 && regionWord.count >= 3 {
                        let lengthDiff = abs(word.count - regionWord.count)
                        if lengthDiff <= 2 {
                            let wordPrefix = String(word.prefix(min(4, word.count)))
                            let regionPrefix = String(regionWord.prefix(min(4, regionWord.count)))
                            if wordPrefix == regionPrefix {
                                foundMatch = true
                                matchType = "fuzzy-prefix"
                                return true
                            }
                        }
                    }
                    return false
                }
                
                if wordMatches {
                    if 1 > bestMatchScore {
                        bestMatch = region
                        bestMatchScore = 1
                        print("   ⭐ New best match (single word): \(region.name)")
                    }
                }
            }
        }
        
        // If we found a good match, use it
        if let match = bestMatch {
            print("✅ [Speech Match] FINAL MATCH: \(match.name) with score \(bestMatchScore)")
            addRegionIfNotFound(match)
        } else {
            print("❌ [Speech Match] NO MATCH FOUND for '\(cleanedText)'")
        }
    }
    
    private func addRegionIfNotFound(_ region: PlateRegion) {
        let row = viewModel.plateRowPresentationsByRegionId[region.id]
        let alreadyFound = row?.isVisuallyFound ?? viewModel.foundRegions.contains(where: { $0.regionID == region.id })
        if !alreadyFound {
            lastMatchedRegion = region
            
            // Check if user wants to skip confirmation
            if viewModel.skipVoiceConfirmation {
                // Auto-add without confirmation
              confirmAddRegion(region, usingTab: .voice)
            } else {
                // Show confirmation popup
                showVoiceMatchConfirmation = true
            }
        } else {
            print("ℹ️ [Speech Match] Region \(region.name) already found, skipping")
        }
    }
    
  private func confirmAddRegion(_ region: PlateRegion, usingTab: FoundRegion.InputMethod) {
        setFound(regionID: region.id, usingTab: usingTab)
        showVoiceMatchConfirmation = false
        lastMatchedRegion = nil
        
        // Clear recognized text and reset processed text after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            speechRecognizer.recognizedText = ""
            lastProcessedText = ""
        }
    }

    private var customTabBar: some View {
//          VStack(spacing: 16) {
//              Image(systemName: "stop.circle.fill")
//                  .font(.system(size: 64))
//                  .foregroundStyle(Color.red.opacity(0.5))
//              Text("Trip Ended")
//                  .font(.system(.title2, design: .rounded))
//                  .fontWeight(.semibold)
//                  .foregroundStyle(Color.Theme.primaryBlue)
//              Text("This trip has been ended. You can no longer add states.")
//                  .font(.system(.body, design: .rounded))
//                  .foregroundStyle(Color.Theme.softBrown)
//                  .multilineTextAlignment(.center)
//                  .padding(.horizontal)
//          }
//          .frame(maxWidth: .infinity, maxHeight: .infinity)
        HStack(spacing: 16) {
            ForEach(Tab.allCases) { tab in
                let isTabDisabled: Bool = !viewModel.isGamePlayActive
                Button {
                    // Prevent switching to tabs if trip is not active
                    if isTabDisabled {
                        return
                    }
                    FeedbackService.shared.selectionChange()
                    withAccessibleAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 20, weight: .semibold))
                            .accessibilityHidden(true)

                        Text(tab.title)
                            .font(.system(.headline, design: .rounded))
                            .fontWeight(.semibold)
                    }
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(selectedTab == tab ? Color.Theme.primaryBlue : Color.Theme.cardBackground)
                    )
                    .foregroundStyle(selectedTab == tab ? Color.white : Color.Theme.primaryBlue)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(selectedTab == tab ? Color.Theme.accentYellow.opacity(0.3) : Color.clear, lineWidth: 3)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isTabDisabled)
                .opacity(isTabDisabled ? 0.5 : 1.0)
                .accessibilityLabel(tab.title)
                .accessibilityValue(selectedTab == tab ? "Selected".localized : "")
                .accessibilityHint(isTabDisabled ? "Trip must be started to use this tab".localized : "Double tap to switch to %@ tab".localized(tab.title.lowercased()))
                .accessibilityAddTraits(selectedTab == tab ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.Theme.cardBackground)
                .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: -3)
                .padding(.horizontal, 12)
                .padding(.vertical, 12	)
        )
    }
  
  private var voiceCapturePlaceholder: some View {
    VStack(spacing: 24) {
      Image(systemName: Tab.voice.systemImage)
        .font(.system(size: 72))
        .foregroundStyle(Color.Theme.accentYellow)
        .padding()
        .background(
          Circle()
            .fill(Color.Theme.cardBackground)
            .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 8)
        )
      
      Text("Voice Coming Soon".localized)
        .font(.system(.title2, design: .rounded))
        .fontWeight(.bold)
        .foregroundStyle(Color.Theme.primaryBlue)
      
      Text("Soon you will be able to log plates hands-free by simply saying the state or province you spot.".localized)
        .font(.system(.body, design: .rounded))
        .foregroundStyle(Color.Theme.softBrown)
        .multilineTextAlignment(.center)
        .padding(.horizontal)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .padding(.top, 20)
  }

}

struct RegionCellView: View {
    let region: PlateRegion
    let presentation: RegionPlateRowPresentation?
    let isSelectedFallback: Bool
    var toggleAction: () -> Void
    var isDisabled: Bool = false
    @State private var showFinderPopover = false

    private var isFound: Bool {
        presentation?.isVisuallyFound ?? isSelectedFallback
    }

    private var finderEntries: [AvatarStackView.AvatarEntry] {
        (presentation?.orderedFinders ?? []).map {
            AvatarStackView.AvatarEntry(
                id: $0.participantId,
                avatarId: $0.avatarId,
                legacyFallbackImageName: $0.legacyFallbackImageName,
                displayName: $0.displayName
            )
        }
    }

    @ViewBuilder
    private var stateBadge: some View {
        if presentation?.showPendingBadge == true {
            XpPendingBadgeView()
        } else if let detail = presentation?.detailLine,
                  !detail.isEmpty,
                  let style = presentation?.detailStyle {
            RegionRowStatusBadgeView(text: detail, style: style)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "licenseplate")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.Theme.primaryBlue)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(region.name)
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.medium)
                            .foregroundStyle(Color.Theme.primaryBlue)
                        
                        
                        Text(region.country.rawValue.localized)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                    }
                    Spacer(minLength: 8)
                    stateBadge
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 10) {
                    if !finderEntries.isEmpty {
                        AvatarStackView(
                            entries: finderEntries,
                            maxDisplay: 3,
                            avatarSize: 22,
                            overlapRatio: 0.38,
                            accessibilityLabel: presentation?.findersAccessibilityValue ?? "finder.stack.accessibility.default".localized,
                            onTap: { showFinderPopover = true }
                        )
                        .popover(isPresented: $showFinderPopover) {
                            FinderOrderPopoverView(
                                title: "finder.popover.title".localized(region.name),
                                finders: presentation?.orderedFinders ?? []
                            )
                        }
                    }
                    Image(systemName: isFound ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(isFound ? Color.Theme.accentYellow : Color.Theme.softBrown.opacity(0.4))
                        .scaleEffect(isFound ? 1.05 : 1.0)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .gesture(
            TapGesture().onEnded {
                if !isDisabled {
                    toggleAction()
                }
            },
            including: .gesture
        )
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1.0)
        .accessibilityLabel(presentation?.accessibilityLabel ?? "\(region.name), \(region.country.rawValue.localized)")
        .accessibilityValue(presentation?.accessibilityValue ?? (isFound ? "Found".localized : "Not found".localized))
        .accessibilityHint(isDisabled ? "Trip must be started to mark regions".localized : "Double tap to %@ this region as found".localized(isFound ? "unmark".localized : "mark".localized))
        .accessibilityAddTraits(.isButton)
    }
}

private struct FinderOrderPopoverView: View {
    let title: String
    let finders: [FinderAvatarPresentation]

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Color.Theme.primaryBlue)
            Text("finder.popover.subtitle".localized)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
            ForEach(Array(finders.enumerated()), id: \.element.id) { index, finder in
                HStack(spacing: 10) {
                    AvatarImageView(
                        avatarId: finder.avatarId,
                        size: 24,
                        showRing: true,
                        legacyFallbackImageName: finder.legacyFallbackImageName
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text("finder.popover.row_title".localized(index + 1, finder.displayName))
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Color.Theme.primaryBlue)
                        Text(Self.formatter.string(from: finder.foundAt))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("finder.popover.row_a11y".localized(index + 1, finder.displayName, Self.formatter.string(from: finder.foundAt)))
            }
        }
        .padding(14)
        .frame(minWidth: 250, maxWidth: 320)
        /// Keep a true popover on compact width (iPhone); default is sheet adaptation.
        .presentationCompactAdaptation(.none)
    }
}

// Custom confirmation dialog for voice recognition
private struct VoiceConfirmationDialog: View {
    let region: PlateRegion
    let onAdd: () -> Void
    let onCancel: () -> Void
    @Binding var skipConfirmation: Bool
    
    var body: some View {
        ConfirmationDialogView(
            title: "Hey, we heard the following %@:".localized(region.country == .canada ? "province".localized : "state".localized),
            content: {
                Text(region.name)
                    .font(.system(.largeTitle, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 4)
                
                Text("Add this to the list of license plates found?".localized)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                    .multilineTextAlignment(.center)
            },
            primaryButtonTitle: "Add".localized,
            primaryAction: onAdd,
            secondaryButtonTitle: "Cancel".localized,
            secondaryAction: onCancel,
            optionalCheckbox: (title: "Don't show this again".localized, isChecked: $skipConfirmation)
        )
    }
}

private extension View {
    /// Stronger layered shadow so top toast/banners read clearly over map and list.
    func gameToastBannerShadow() -> some View {
        self
            .shadow(color: .black.opacity(0.16), radius: 5, x: 0, y: 2)
            .shadow(color: .black.opacity(0.28), radius: 22, x: 0, y: 12)
    }
}
