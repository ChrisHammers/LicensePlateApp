//
//  CombinedTripSetupView.swift
//  LicensePlateApp
//
//  Step 06 — Combined trip setup: select game types, countries, and options. Creates TripSession + GameInstances + legacy Trip.
//

import SwiftUI
import SwiftData

struct CombinedTripSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @StateObject private var viewModel: CombinedTripSetupViewModel
    var onCreated: (Trip) -> Void

    init(
        viewModel: CombinedTripSetupViewModel,
        onCreated: @escaping (Trip) -> Void
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onCreated = onCreated
    }

    @AppStorage("appPlaySoundEffects") private var appPlaySoundEffects = true
    @AppStorage("appUseVibrations") private var appUseVibrations = true

    var body: some View {
        NavigationStack {
            ZStack {
                Color.Theme.background
                    .ignoresSafeArea()

                List {
                    basicInfoSection
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
                AnalyticsService.shared.log(.combinedTripSetupOpened)
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
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .disabled(!viewModel.canCreate || viewModel.isCreating)
                    .accessibilityLabel("Create".localized)
                    .accessibilityHint("Creates the trip with selected games and options".localized)
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

                    CombinedTripCountryRow(title: "United States".localized, isOn: $viewModel.includeUS)
                    CombinedTripCountryRow(title: "Canada".localized, isOn: $viewModel.includeCanada)
                    CombinedTripCountryRow(title: "Mexico".localized, isOn: $viewModel.includeMexico)
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

    private func createTapped() {
        FeedbackService.shared.buttonTap()
        viewModel.clearError()
        do {
            let trip = try viewModel.createTrip(modelContext: modelContext)
            FeedbackService.shared.actionSuccess()
            onCreated(trip)
            dismiss()
        } catch {
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

// MARK: - Country row

private struct CombinedTripCountryRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(title)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.Theme.primaryBlue)

            Spacer()

            Toggle("", isOn: $isOn)
                .tint(Color.Theme.primaryBlue)
                .labelsHidden()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.Theme.background)
        )
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On".localized : "Off".localized)
    }
}

// MARK: - Previews

#Preview("Combined Trip Setup") {
    CombinedTripSetupView(
        viewModel: CombinedTripSetupViewModel(
            tripSessionRepository: TripSessionRepository.shared,
            gameInstanceRepository: GameInstanceRepository.shared,
            authService: FirebaseAuthService()
        ),
        onCreated: { _ in }
    )
    .modelContainer(for: [Trip.self, TripSessionEntity.self, GameInstanceEntity.self], inMemory: true)
}

#Preview("Combined Trip Setup - With name") {
    let vm = CombinedTripSetupViewModel(
        tripSessionRepository: TripSessionRepository.shared,
        gameInstanceRepository: GameInstanceRepository.shared,
        authService: FirebaseAuthService()
    )
    vm.tripName = "Weekend Road Trip"
    return CombinedTripSetupView(viewModel: vm, onCreated: { _ in })
        .modelContainer(for: [Trip.self, TripSessionEntity.self, GameInstanceEntity.self], inMemory: true)
}
