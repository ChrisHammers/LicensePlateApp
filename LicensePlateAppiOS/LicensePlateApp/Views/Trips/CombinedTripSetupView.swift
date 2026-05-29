//
//  CombinedTripSetupView.swift
//  LicensePlateApp
//
//  Step 06 — Combined trip setup: select game types, countries, and options. Creates TripSession + GameInstances (canonical only).
//

import SwiftUI
import SwiftData

struct CombinedTripSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authService: FirebaseAuthService

    @StateObject private var viewModel: CombinedTripSetupViewModel
    var onCreated: (TripSession) -> Void
    @State private var isShowingPassengerSelector = false
    @StateObject private var tripLimitPaywallViewModel = PaywallViewModel()

    init(
        viewModel: CombinedTripSetupViewModel,
        onCreated: @escaping (TripSession) -> Void
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onCreated = onCreated
    }

    @AppStorage("appPlaySoundEffects") private var appPlaySoundEffects = true
    @AppStorage("appUseVibrations") private var appUseVibrations = true

    /// Explicit bindings for pickers (same pattern as `AppPreferencesView` private picker bindings).
    private var defaultGameModeBinding: Binding<GameMode> {
        Binding(
            get: { viewModel.defaultGameMode },
            set: { viewModel.defaultGameMode = $0 }
        )
    }

    var body: some View {
        NavigationStack {
            AppBackgroundView {
                List {
                    if viewModel.shouldShowSetupAd {
                        adSection
                    }
                    basicInfoSection
                    tripParticipationSection
                    gamesSection
                    tripOptionsSection
                    tripSettingsSection
                 
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("New Trip".localized)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                FeedbackService.shared.updatePreferences(hapticEnabled: appUseVibrations, soundEnabled: appPlaySoundEffects)
                viewModel.logSetupScreenAppeared()
            }
            .onChange(of: appUseVibrations) { _, newValue in
                FeedbackService.shared.updatePreferences(hapticEnabled: newValue, soundEnabled: appPlaySoundEffects)
            }
            .onChange(of: appPlaySoundEffects) { _, newValue in
                FeedbackService.shared.updatePreferences(hapticEnabled: appUseVibrations, soundEnabled: newValue)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel".localized) {
                        FeedbackService.shared.buttonTap()
                        dismiss()
                    }
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .accessibilityLabel("Cancel".localized)
                    .accessibilityHint("Cancels creating a new trip".localized)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create".localized) {
                        createTapped()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(!viewModel.canCreate || viewModel.isCreating ? .secondary : Color.Theme.primaryBlue)
                    .disabled(!viewModel.canCreate || viewModel.isCreating)
                    .accessibilityLabel("Create".localized)
                    .accessibilityHint(!viewModel.canCreate ? "Select at least one country before saving.".localized : "Creates the trip with selected games and options".localized
                    )
                }
            }
            .alert("Error".localized, isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.clearError() } }
            )) {
                Button("OK".localized) { viewModel.clearError() }
            } message: {
                if let msg = viewModel.errorMessage {
                    Text(msg)
                }
            }
            .sheet(isPresented: $isShowingPassengerSelector) {
                InvitePlayersView(
                    viewModel: InvitePlayersViewModel(
                        mode: .setupSelection,
                        tripSessionId: UUID(),
                        tripName: viewModel.tripName,
                        selectedUserIds: viewModel.selectedPassengerIds,
                        authService: authService
                    ),
                    title: "Passenger List".localized
                ) { selected in
                    viewModel.selectedPassengerIds = selected
                }
                .environmentObject(authService)
            }
            .sheet(isPresented: Binding(
                get: { viewModel.shouldPresentTripLimitPaywall },
                set: { if !$0 { viewModel.dismissTripLimitPaywall() } }
            )) {
                PaywallView(
                    viewModel: tripLimitPaywallViewModel,
                    onDismiss: { viewModel.dismissTripLimitPaywall() },
                    source: TripLimitGateSource.create.rawValue
                )
                .onAppear {
                    tripLimitPaywallViewModel.setTripLimitContext()
                }
            }
        }
    }

    private var basicInfoSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Trip Name".localized)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Color.Theme.primaryBlue)

                TextField("Automatically use date & time".localized, text: $viewModel.tripName)
                    .textInputAutocapitalization(.words)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.Theme.background)
                    )
                    .accessibilityLabel("Trip Name".localized)
                    .accessibilityHint("Enter a name for your trip, or leave blank to use date and time".localized)
                    .accessibilityValue(viewModel.tripName.isEmpty ? "Will use date and time".localized : viewModel.tripName)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(Color.Theme.cardBackground)
            .cornerRadius(20)
            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
            .listRowBackground(Color.clear)
        } header: {
            Text("Basic Info".localized)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Color.Theme.primaryBlue)
        }
        .textCase(nil)
    }

    private var tripParticipationSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Passenger List".localized)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Color.Theme.primaryBlue)

                Text("Your trip starts with you. Invite friends or family anytime to play together.".localized)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Your trip starts with you. Invite friends or family anytime to play together.".localized)

                Button {
                    FeedbackService.shared.buttonTap()
                    isShowingPassengerSelector = true
                } label: {
                    HStack {
                        Label("Passenger List".localized, systemImage: "person.2.fill")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Color.Theme.primaryBlue)
                        Spacer()
                        Text(viewModel.selectedPassengerIds.isEmpty ? "Optional".localized : "%d selected".localized(viewModel.selectedPassengerIds.count))
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.Theme.background)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Passenger List".localized)
                .accessibilityHint("Select friends or family to invite after trip creation".localized)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(Color.Theme.cardBackground)
            .cornerRadius(20)
            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
            .listRowBackground(Color.clear)
        } header: {
            Text("Trip".localized)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Color.Theme.primaryBlue)
        }
        .textCase(nil)
    }

    private var gamesSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Games to play".localized)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Color.Theme.primaryBlue)

                Text("Choose one or more games for this trip. You can add more later.".localized)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)

                ForEach(GameType.availableTypes, id: \.self) { gameType in
                    GameTypeRow(
                        gameType: gameType,
                        isSelected: viewModel.selectedGameTypes.contains(gameType),
                        onToggle: { viewModel.toggleGameType(gameType) }
                    )
                }

                Text("Play style applies to each selected game.".localized)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                    .accessibilityLabel("Play style applies to each selected game.".localized)

                Picker(selection: defaultGameModeBinding) {
                    Text("Collaborative".localized).tag(GameMode.collaborative)
                    Text("Competitive".localized).tag(GameMode.competitive)
                } label: {
                    Text("Play style".localized)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Game play style".localized)
                .accessibilityHint("Collaborative shares credit. Competitive scores individually.".localized)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(Color.Theme.cardBackground)
            .cornerRadius(20)
            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
            .listRowBackground(Color.clear)
        } header: {
            Text("Games".localized)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Color.Theme.primaryBlue)
        }
        .textCase(nil)
    }

    private var tripOptionsSection: some View {
        Section {
            VStack(spacing: 12) {
                SettingToggleRow(
                    title: "Start Trip right away".localized,
                    description: "Automatically start the trip when created".localized,
                    isOn: $viewModel.startTripRightAway
                )

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Countries to Include".localized)
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(Color.Theme.primaryBlue)

                    SettingToggleRow(title: "United States".localized, isOn: $viewModel.includeUS)
                        .onChange(of: viewModel.includeUS) { _, _ in
                            viewModel.applyTerritoryGatingFromCountryToggles()
                        }
                    SettingToggleRow(title: "Canada".localized, isOn: $viewModel.includeCanada)
                        .onChange(of: viewModel.includeCanada) { _, _ in
                            viewModel.applyTerritoryGatingFromCountryToggles()
                        }
                    SettingToggleRow(title: "Mexico".localized, isOn: $viewModel.includeMexico)

                    Text("Enable United States to configure US territories and Washington, DC. Enable Canada for Canadian territories.".localized)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                        .accessibilityLabel("Enable United States to configure US territories and Washington, DC. Enable Canada for Canadian territories.".localized)

                    SettingToggleRow(
                        title: "Include US Territories".localized,
                        description: "Puerto Rico, Guam, US Virgin Islands, American Samoa, Northern Mariana Islands".localized,
                        isOn: $viewModel.includeUSTerritories
                    )
                    .disabled(!viewModel.includeUS)
                    .opacity(viewModel.includeUS ? 1.0 : 0.5)
                    .accessibilityHint(viewModel.includeUS ? "" : "Enable United States first".localized)

                    SettingToggleRow(
                        title: "Include Washington, DC".localized,
                        description: "District of Columbia as its own plate region".localized,
                        isOn: $viewModel.includeDC
                    )
                    .disabled(!viewModel.includeUS)
                    .opacity(viewModel.includeUS ? 1.0 : 0.5)
                    .accessibilityHint(viewModel.includeUS ? "" : "Enable United States first".localized)

                    SettingToggleRow(
                        title: "Include Canadian Territories".localized,
                        description: "Nunavut, Northwest Territories, Yukon".localized,
                        isOn: $viewModel.includeCanadianTerritories
                    )
                    .disabled(!viewModel.includeCanada)
                    .opacity(viewModel.includeCanada ? 1.0 : 0.5)
                    .accessibilityHint(viewModel.includeCanada ? "" : "Enable Canada first".localized)

                    if let message = viewModel.countryValidationMessage {
                        Text(message)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.red)
                            .accessibilityLabel(message)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(Color.Theme.cardBackground)
            .cornerRadius(20)
            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
            .listRowBackground(Color.clear)
        } header: {
            Text("Trip Options".localized)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Color.Theme.primaryBlue)
        }
        .textCase(nil)
    }

    private var tripSettingsSection: some View {
        Section {
            VStack(spacing: 12) {
                SettingToggleRow(
                    title: "Skip Voice Confirmation".localized,
                    description: "Automatically add license plates without confirmation when using Voice".localized,
                    isOn: $viewModel.skipVoiceConfirmation
                )

                Divider()

                SettingToggleRow(
                    title: "Save location when marking plates".localized,
                    description: "Store location data when you mark a plate as found".localized,
                    isOn: $viewModel.saveLocationWhenMarkingPlates
                )

                Divider()

                SettingToggleRow(
                    title: "Show my location on large map".localized,
                    description: "Display your current location on the full-screen map".localized,
                    isOn: $viewModel.showMyLocationOnLargeMap
                )

                Divider()

                SettingToggleRow(
                    title: "Track my location during trip".localized,
                    description: "Continuously track your location while a trip is active".localized,
                    isOn: $viewModel.trackMyLocationDuringTrip
                )

                Divider()

                SettingToggleRow(
                    title: "Show my active trip on the large map".localized,
                    description: "Display your active trip on the full-screen map".localized,
                    isOn: $viewModel.showMyActiveTripOnLargeMap
                )
                .disabled(!viewModel.trackMyLocationDuringTrip)
                .opacity(viewModel.trackMyLocationDuringTrip ? 1.0 : 0.5)

                Divider()

                SettingToggleRow(
                    title: "Show my active trip on the small map".localized,
                    description: "Display your active trip on the small map".localized,
                    isOn: $viewModel.showMyActiveTripOnSmallMap
                )
                .disabled(!viewModel.trackMyLocationDuringTrip)
                .opacity(viewModel.trackMyLocationDuringTrip ? 1.0 : 0.5)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(Color.Theme.cardBackground)
            .cornerRadius(20)
            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
            .listRowBackground(Color.clear)
        } header: {
            Text("Trip Settings".localized)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Color.Theme.primaryBlue)
        }
        .textCase(nil)
    }

    private var adSection: some View {
        Section {
            AdBannerView(surface: .combinedTripSetup)
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                .listRowBackground(Color.clear)
        }
        .textCase(nil)
    }

    private func createTapped() {
        FeedbackService.shared.buttonTap()
        viewModel.clearError()
        do {
            let session = try viewModel.createTrip()
            Task {
                // Invites seed `members/{owner}` on Firestore before canonical publish (callable requires owner member).
                await viewModel.sendSetupInvites(for: session)
                await viewModel.publishCanonicalToRemote(session: session)
            }
            FeedbackService.shared.actionSuccess()
            onCreated(session)
            dismiss()
        } catch {
            if error is TripEntitlementGateError {
                tripLimitPaywallViewModel.setTripLimitContext()
                FeedbackService.shared.actionError()
                return
            }
            viewModel.setError(error.localizedDescription)
            FeedbackService.shared.actionError()
        }
    }
}

// MARK: - Game type row

private struct GameTypeRow: View {
    let gameType: GameType
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(gameType.displayName)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.medium)
                        .foregroundStyle(Color.Theme.primaryBlue)
                    if let desc = gameType.shortDescription {
                        Text(desc)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                    }
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.Theme.primaryBlue : Color.Theme.softBrown)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.Theme.background)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(gameType.displayName)
        .accessibilityValue(isSelected ? "Selected".localized : "Not selected".localized)
        .accessibilityHint("Toggle this game for the trip".localized)
    }
}

// MARK: - Previews

#Preview("Combined Trip Setup") {
    let auth = FirebaseAuthService()
    auth.currentUser = AppUser(id: "preview-user", userName: "Preview", firebaseUID: "preview-user")
    return CombinedTripSetupView(
        viewModel: CombinedTripSetupViewModel(
            tripSessionRepository: TripSessionRepository.shared,
            gameInstanceRepository: GameInstanceRepository.shared,
            authService: auth
        ),
        onCreated: { _ in }
    )
    .environmentObject(auth)
    .modelContainer(for: [TripSessionEntity.self, GameInstanceEntity.self, TripActivityEventEntity.self], inMemory: true)
}

#Preview("Combined Trip Setup - With name") {
    let auth = FirebaseAuthService()
    auth.currentUser = AppUser(id: "preview-user", userName: "Preview", firebaseUID: "preview-user")
    let vm = CombinedTripSetupViewModel(
        tripSessionRepository: TripSessionRepository.shared,
        gameInstanceRepository: GameInstanceRepository.shared,
        authService: auth
    )
    vm.tripName = "Weekend Road Trip"
    return CombinedTripSetupView(viewModel: vm, onCreated: { _ in })
        .environmentObject(auth)
        .modelContainer(for: [TripSessionEntity.self, GameInstanceEntity.self, TripActivityEventEntity.self], inMemory: true)
}

#Preview("Combined Trip Setup - Ad Banner") {
    AdBannerView(surface: .combinedTripSetup, isPreviewPlaceholder: true)
        .padding()
}
