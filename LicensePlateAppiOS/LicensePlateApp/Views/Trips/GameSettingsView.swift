//
//  GameSettingsView.swift
//  LicensePlateApp
//
//  Step 6.9.3.1 — Game-level settings: scope, reset/remove game, tracking & voice defaults. Opened from LicensePlateGameView.
//

import SwiftUI
import CoreLocation

struct GameSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: LicensePlateGameViewModel
    var onGameInstanceRemoved: (() -> Void)? = nil

    @State private var retryAction: (() -> Void)?
    @State private var showEndGameConfirmation = false

    @AppStorage("defaultSaveLocationWhenMarkingPlates") private var saveLocationWhenMarkingPlates = true
    @AppStorage("defaultShowMyLocationOnLargeMap") private var showMyLocationOnLargeMap = true
    @AppStorage("defaultTrackMyLocationDuringTrip") private var trackMyLocationDuringTrip = true
    @AppStorage("defaultShowMyActiveTripOnLargeMap") private var showMyActiveTripOnLargeMap = true
    @AppStorage("defaultShowMyActiveTripOnSmallMap") private var showMyActiveTripOnSmallMap = true
    @AppStorage("defaultSkipVoiceConfirmation") private var skipVoiceConfirmation = false
    @AppStorage("defaultHoldToTalk") private var holdToTalk = true

    enum SettingsSection: String, CaseIterable {
        case gameInfo = "Game info"
        case gameSettings = "Game Settings"
        case trackingPrivacy = "Tracking & Privacy"
        case voice = "Voice"
        case gameActions = "Game actions"

        var id: String { rawValue }

        var localizedTitle: String {
            switch self {
            case .gameInfo: return "Game info".localized
            case .gameSettings: return "Game Settings".localized
            case .trackingPrivacy: return "Tracking & Privacy".localized
            case .voice: return "Voice".localized
            case .gameActions: return "Game actions".localized
            }
        }
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }

    @StateObject private var locationManager = LocationManager()

    @State private var showResetConfirmation = false
    @State private var showRemoveGameConfirmation = false

    private var isTripTerminalForGameReset: Bool {
        viewModel.currentSession.status == .ended || viewModel.currentSession.status == .cancelled
    }

    var body: some View {
        NavigationStack {
            AppBackgroundView {
                List {
                    ForEach(SettingsSection.allCases, id: \.id) { section in
                        Section {
                            VStack {
                                switch section {
                                case .gameInfo:
                                    gameInfoContent
                                case .gameSettings:
                                    gameSettings
                                case .trackingPrivacy:
                                    trackingPrivacySettings
                                case .voice:
                                    voiceSettings
                                case .gameActions:
                                    gameActionsContent
                                }
                            }
                            .background(Color.Theme.cardBackground)
                            .cornerRadius(20)
                        } header: {
                            Text(section.localizedTitle)
                                .font(.system(.headline, design: .rounded))
                                .foregroundStyle(Color.Theme.primaryBlue)
                        }
                        .textCase(nil)
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Game settings".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done".localized) {
                        do {
                            try viewModel.commitLicensePlateScopeDraft()
                            dismiss()
                        } catch {
                            viewModel.setError(error.localizedDescription)
                        }
                    }
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(!(viewModel.licensePlateScopeDraft?.canSave ?? false) ? .secondary : Color.Theme.primaryBlue)
                    .disabled(!(viewModel.licensePlateScopeDraft?.canSave ?? false))
                    .accessibilityLabel("Done".localized)
                    .accessibilityHint(!(viewModel.licensePlateScopeDraft?.canSave ?? false) ? "Select at least one country before saving.".localized : "Done editing changes, saves game scope, and dismisses game settings".localized
                    )
                }
            }
        }
        .onAppear {
            viewModel.refreshGame()
            viewModel.beginLicensePlateScopeDraft()
        }
        .onDisappear {
            viewModel.discardLicensePlateScopeDraft()
        }
    }

    private var gameInfoContent: some View {
        Group {
            let displayName = GameType(rawValue: viewModel.game.definitionId)?.displayName ?? viewModel.game.definitionId
            SettingInfoRow(title: "Name".localized, value: displayName)

            Divider()

            SettingInfoRow(
                title: "Status".localized,
                value: localizedGameLifecycleState(viewModel.game.commonConfig.lifecycleState)
            )

            if let endedAt = viewModel.game.endedAt {
                Divider()
                SettingInfoRow(title: "Ended".localized, value: dateFormatter.string(from: endedAt))
            }

            Divider()

            if viewModel.currentSession.status == .ended || viewModel.currentSession.status == .cancelled {
                Text(viewModel.currentSession.status == .cancelled
                    ? "This trip was cancelled; game actions are unavailable.".localized
                    : "This trip has ended; game actions are unavailable.".localized
                )
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
                .padding(.vertical, 8)
                .accessibilityLabel(viewModel.currentSession.status == .cancelled
                    ? "This trip was cancelled; game actions are unavailable.".localized
                    : "This trip has ended; game actions are unavailable.".localized
                )
            } else if !viewModel.isTripContainerActive {
                Text("Start the trip from trip settings before starting this game.".localized)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                    .padding(.vertical, 8)
                    .accessibilityLabel("Start the trip from trip settings before starting this game.".localized)
            } else if viewModel.game.commonConfig.lifecycleState == .created {
                Button {
                    do {
                        try viewModel.startGame()
                    } catch {
                        viewModel.setError(error.localizedDescription)
                        retryAction = { try? viewModel.startGame() }
                    }
                } label: {
                    HStack {
                        Text("Start Game".localized)
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.Theme.primaryBlue)
                            .frame(maxWidth: .infinity, maxHeight: 50)
                            .padding(.horizontal, 6)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.isTripCreator)
                .opacity(viewModel.isTripCreator ? 1.0 : 0.5)
                .accessibilityLabel("Start Game".localized)
                .accessibilityHint(viewModel.isTripCreator ? "Starts this game so you can mark plates".localized : "Only the trip creator can start the game".localized)

                Divider()
            } else if viewModel.game.commonConfig.lifecycleState == .started {
                Button {
                    showEndGameConfirmation = true
                } label: {
                    HStack {
                        Text("End Game".localized)
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.red)
                            .frame(maxWidth: .infinity, maxHeight: 50)
                            .padding(.horizontal, 6)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.isTripCreator)
                .opacity(viewModel.isTripCreator ? 1.0 : 0.5)
                .accessibilityLabel("End Game".localized)
                .accessibilityHint(viewModel.isTripCreator ? "Ends this game for this trip".localized : "Only the trip creator can end the game".localized)

                Divider()
            } else {
                Text(
                    viewModel.game.commonConfig.lifecycleState == .completed
                        ? "This game is complete. Reset it from Game actions to play again.".localized
                        : "This game has ended. Reset it from Game actions to play again.".localized
                )
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(
                    viewModel.game.commonConfig.lifecycleState == .completed
                        ? "This game is complete. Reset it from Game actions to play again.".localized
                        : "This game has ended. Reset it from Game actions to play again.".localized
                )
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

    private func localizedGameLifecycleState(_ state: GameInstanceState) -> String {
        switch state {
        case .created: return "Not started".localized
        case .started: return "In progress".localized
        case .ended: return "Ended".localized
        case .completed: return "Completed".localized
        }
    }

    private var gameSettings: some View {
        Group {
            let canEditCountries = viewModel.currentSession.startedAt == nil && !viewModel.game.commonConfig.configLocked

            if let draft = viewModel.licensePlateScopeDraft {
                LicensePlateGameScopeDraftSection(draft: draft, canEditCountries: canEditCountries)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            }
        }
    }

    private var gameActionsContent: some View {
        Group {
            Button {
                showResetConfirmation = true
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Reset Game".localized)
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundStyle(isTripTerminalForGameReset ? Color.secondary : Color.Theme.primaryBlue)
                        Spacer()
                    }
                    if isTripTerminalForGameReset {
                        Text("Reset is not available for ended or cancelled trips.".localized)
                            .font(.caption)
                            .foregroundStyle(Color.Theme.softBrown)
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.isTripCreator || isTripTerminalForGameReset)

            Divider()

            Button {
                showRemoveGameConfirmation = true
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Remove this game".localized)
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundStyle(viewModel.canRemoveThisGameInstance ? Color.Theme.primaryBlue : Color.secondary)
                        Spacer()
                    }
                    if !viewModel.canRemoveThisGameInstance, viewModel.isTripCreator, !isTripTerminalForGameReset {
                        Text("Only available when the trip has more than one game.".localized)
                            .font(.caption)
                            .foregroundStyle(Color.Theme.softBrown)
                    } else if isTripTerminalForGameReset {
                        Text("Remove game is not available for ended or cancelled trips.".localized)
                            .font(.caption)
                            .foregroundStyle(Color.Theme.softBrown)
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canRemoveThisGameInstance)
        }
        .alert("Reset Game".localized, isPresented: $showResetConfirmation) {
            Button("Cancel".localized, role: .cancel) {}
            Button("Reset".localized, role: .destructive) {
                do {
                    try viewModel.resetGame()
                } catch {
                    viewModel.setError(error.localizedDescription)
                    retryAction = { try? viewModel.resetGame() }
                }
            }
        } message: {
            Text("Only this game's progress will be reset (discoveries and game state). The trip and its dates will not be changed.".localized)
        }
        .alert("Remove this game".localized, isPresented: $showRemoveGameConfirmation) {
            Button("Cancel".localized, role: .cancel) {}
            Button("Remove".localized, role: .destructive) {
                do {
                    try viewModel.deleteGameInstance()
                    dismiss()
                    onGameInstanceRemoved?()
                } catch {
                    viewModel.setError(error.localizedDescription)
                    retryAction = { try? viewModel.deleteGameInstance(); dismiss(); onGameInstanceRemoved?() }
                }
            }
        } message: {
            Text("This removes only this game from the trip. The trip continues with your other games.".localized)
        }
    }

    private var trackingPrivacySettings: some View {
        Group {
            let locationAuthorized = locationManager.authorizationStatus == .authorizedWhenInUse || locationManager.authorizationStatus == .authorizedAlways
            let canEditTracking = viewModel.currentSession.status != .ended

            SettingToggleRow(
                title: "Save location when marking plates".localized,
                description: "Store location data when you mark a plate as found".localized,
                isOn: $saveLocationWhenMarkingPlates
            )
            .disabled(!locationAuthorized || !canEditTracking)
            .opacity((locationAuthorized && canEditTracking) ? 1.0 : 0.5)

            Divider()

            SettingToggleRow(
                title: "Show my location on large map".localized,
                description: "Display your current location on the full-screen map".localized,
                isOn: $showMyLocationOnLargeMap
            )
            .disabled(!canEditTracking)
            .opacity(canEditTracking ? 1.0 : 0.5)

            Divider()

            SettingToggleRow(
                title: "Track my location during trip".localized,
                description: "Continuously track your location while a trip is active".localized,
                isOn: $trackMyLocationDuringTrip
            )
            .disabled(!canEditTracking)
            .opacity(canEditTracking ? 1.0 : 0.5)

            Divider()

            SettingToggleRow(
                title: "Show my active trip on the large map".localized,
                description: "Display your active trip on the full-screen map".localized,
                isOn: $showMyActiveTripOnLargeMap
            )
            .disabled(!trackMyLocationDuringTrip || !canEditTracking)
            .opacity((trackMyLocationDuringTrip && canEditTracking) ? 1.0 : 0.5)

            Divider()

            SettingToggleRow(
                title: "Show my active trip on the small map".localized,
                description: "Display your active trip on the small map".localized,
                isOn: $showMyActiveTripOnSmallMap
            )
            .disabled(!trackMyLocationDuringTrip || !canEditTracking)
            .opacity((trackMyLocationDuringTrip && canEditTracking) ? 1.0 : 0.5)
        }
    }

    private var voiceSettings: some View {
        Group {
            let canEditSettings = viewModel.currentSession.status != .ended

            SettingToggleRow(
                title: "Skip Voice Confirmation".localized,
                description: "Automatically add license plates without confirmation when using Voice".localized,
                isOn: $skipVoiceConfirmation
            )
            .disabled(!canEditSettings)
            .opacity(canEditSettings ? 1.0 : 0.5)
            if false {
                SettingToggleRow(
                    title: "Hold to Talk",
                    description: "Press and hold the microphone button to record. If disabled the system will listen until you hit stop.",
                    isOn: $holdToTalk
                )
                .disabled(!canEditSettings)
                .opacity(canEditSettings ? 1.0 : 0.5)
            }
        }
    }
}

/// Countries + territory scope edited in Game Settings; persisted when user taps Done on the sheet.
private struct LicensePlateGameScopeDraftSection: View {
    @ObservedObject var draft: LicensePlateScopeSettingsDraft
    let canEditCountries: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Countries to Include".localized)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Color.Theme.primaryBlue)
                .padding(.bottom, 4)

            SettingToggleRow(
                title: "United States".localized,
                isOn: Binding(
                    get: { draft.includeUS },
                    set: { newValue in
                        draft.includeUS = newValue
                        draft.applyParentGating()
                    }
                )
            )
            .disabled(!canEditCountries)
            .opacity(canEditCountries ? 1.0 : 0.5)

            SettingToggleRow(
                title: "Canada".localized,
                isOn: Binding(
                    get: { draft.includeCanada },
                    set: { newValue in
                        draft.includeCanada = newValue
                        draft.applyParentGating()
                    }
                )
            )
            .disabled(!canEditCountries)
            .opacity(canEditCountries ? 1.0 : 0.5)

            SettingToggleRow(
                title: "Mexico".localized,
                isOn: Binding(
                    get: { draft.includeMexico },
                    set: { newValue in
                        draft.includeMexico = newValue
                    }
                )
            )
            .disabled(!canEditCountries)
            .opacity(canEditCountries ? 1.0 : 0.5)

            Text("Enable United States to configure US territories and Washington, DC. Enable Canada for Canadian territories.".localized)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
                .accessibilityLabel("Enable United States to configure US territories and Washington, DC. Enable Canada for Canadian territories.".localized)

            SettingToggleRow(
                title: "Include US Territories".localized,
                description: "Puerto Rico, Guam, US Virgin Islands, American Samoa, Northern Mariana Islands".localized,
                isOn: $draft.includeUSTerritories
            )
            .disabled(!canEditCountries || !draft.includeUS)
            .opacity((canEditCountries && draft.includeUS) ? 1.0 : 0.5)
            .accessibilityHint((canEditCountries && draft.includeUS) ? "" : "Enable United States first".localized)

            SettingToggleRow(
                title: "Include Washington, DC".localized,
                description: "District of Columbia as its own plate region".localized,
                isOn: $draft.includeDC
            )
            .disabled(!canEditCountries || !draft.includeUS)
            .opacity((canEditCountries && draft.includeUS) ? 1.0 : 0.5)
            .accessibilityHint((canEditCountries && draft.includeUS) ? "" : "Enable United States first".localized)

            SettingToggleRow(
                title: "Include Canadian Territories".localized,
                description: "Nunavut, Northwest Territories, Yukon".localized,
                isOn: $draft.includeCanadianTerritories
            )
            .disabled(!canEditCountries || !draft.includeCanada)
            .opacity((canEditCountries && draft.includeCanada) ? 1.0 : 0.5)
            .accessibilityHint((canEditCountries && draft.includeCanada) ? "" : "Enable Canada first".localized)

            if let message = draft.countryValidationMessage {
                Text(message)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.red)
                    .accessibilityLabel(message)
            }
        }
    }
}

#Preview("Game settings") {
    let sessionId = UUID()
    let gameId = UUID()
    let session = TripSession(
        id: sessionId,
        name: "Preview",
        status: .active,
        createdAt: Date(),
        createdBy: "u1",
        startedAt: Date(),
        participants: []
    )
    let game = GameInstance(
        id: gameId,
        definitionId: GameType.licensePlate.rawValue,
        sessionId: sessionId,
        ruleSet: GameRuleSet(gameDefinitionId: "license_plate"),
        commonConfig: CommonGameConfig(lifecycleState: .created, configLocked: false, configLockReason: .none)
    )
    let auth = FirebaseAuthService()
    auth.currentUser = AppUser(id: "u1", userName: "U", firebaseUID: "u1")
    return GameSettingsView(
        viewModel: LicensePlateGameViewModel(
            session: session,
            game: game,
            tripSessionRepository: TripSessionRepository.shared,
            gameInstanceRepository: GameInstanceRepository.shared,
            tripActivityEventRepository: TripActivityEventRepository.shared,
            lifecycleService: TripSessionLifecycleService.shared,
            authService: auth
        )
    )
}
