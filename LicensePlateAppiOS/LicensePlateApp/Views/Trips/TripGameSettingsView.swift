//
//  TripGameSettingsView.swift
//  LicensePlateApp
//
//  Step 6.8 — Game/trip settings sheet. Extracted from TripTrackerView for use by LicensePlateGameView.
//

import SwiftUI
import CoreLocation

/// Settings sheet for the license plate game: trip info, countries, tracking, voice. Used by LicensePlateGameView.
struct TripGameSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: LicensePlateGameViewModel
    let game: GameInstance

    @State private var retryAction: (() -> Void)?

    @AppStorage("defaultSaveLocationWhenMarkingPlates") private var saveLocationWhenMarkingPlates = true
    @AppStorage("defaultShowMyLocationOnLargeMap") private var showMyLocationOnLargeMap = true
    @AppStorage("defaultTrackMyLocationDuringTrip") private var trackMyLocationDuringTrip = true
    @AppStorage("defaultShowMyActiveTripOnLargeMap") private var showMyActiveTripOnLargeMap = true
    @AppStorage("defaultShowMyActiveTripOnSmallMap") private var showMyActiveTripOnSmallMap = true
    @AppStorage("defaultSkipVoiceConfirmation") private var skipVoiceConfirmation = false
    @AppStorage("defaultHoldToTalk") private var holdToTalk = true

    enum SettingsSection: String, CaseIterable {
        case tripInfo = "Trip Info"
        case gameSettings = "Game Settings"
        case trackingPrivacy = "Tracking & Privacy"
        case voice = "Voice"

        var id: String { rawValue }

        var localizedTitle: String {
            switch self {
            case .tripInfo: return "Trip Info".localized
            case .gameSettings: return "Game Settings".localized
            case .trackingPrivacy: return "Tracking & Privacy".localized
            case .voice: return "Voice".localized
            }
        }
    }

    @EnvironmentObject var authService: FirebaseAuthService
    @StateObject private var locationManager = LocationManager()

    @State private var showEndTripConfirmation = false
    @State private var showResetConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var isEditingTripName = false
    @State private var editingTripName: String = ""
    @State private var includeUS: Bool = false
    @State private var includeCanada: Bool = false
    @State private var includeMexico: Bool = false

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.Theme.background
                    .ignoresSafeArea()

                List {
                    ForEach(SettingsSection.allCases, id: \.id) { section in
                        Section {
                            VStack {
                                switch section {
                                case .tripInfo:
                                    tripInfoSettings
                                case .gameSettings:
                                    gameSettings
                                case .trackingPrivacy:
                                    trackingPrivacySettings
                                case .voice:
                                    voiceSettings
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
        }
        .background(Color.Theme.background)
        .onAppear {
            syncCountryTogglesFromGameConfig()
        }
    }

    private var tripInfoSettings: some View {
        Group {
            SettingEditableTextRow(
                title: "Trip Name".localized,
                value: Binding(
                    get: { viewModel.currentSession.name },
                    set: { newValue in
                        viewModel.updateTripName(newValue)
                    }
                ),
                placeholder: "Enter trip name".localized,
                isDisabled: !viewModel.isTripCreator,
                onSave: {
                    viewModel.saveSession()
                },
                onCancel: {}
            )

            Divider()

            if let startedAt = viewModel.currentSession.startedAt {
                SettingInfoRow(
                    title: "Started".localized,
                    value: dateFormatter.string(from: startedAt)
                )
                Divider()
            } else {
                SettingInfoRow(
                    title: "Created".localized,
                    value: dateFormatter.string(from: viewModel.currentSession.createdAt)
                )
                Divider()
            }

            if viewModel.currentSession.startedAt == nil {
                Button {
                    do {
                        try viewModel.startTrip()
                    } catch {
                        viewModel.setError(error.localizedDescription)
                        retryAction = { try? viewModel.startTrip() }
                    }
                } label: {
                    HStack {
                        Text("Start Trip".localized)
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
            }

            Divider()

            if viewModel.currentSession.startedAt != nil && viewModel.currentSession.status != .ended {
                Button {
                    showEndTripConfirmation = true
                } label: {
                    HStack {
                        Text("End Trip".localized)
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

                Divider()
            } else if let endedAt = viewModel.currentSession.endedAt {
                SettingInfoRow(
                    title: "Ended".localized,
                    value: dateFormatter.string(from: endedAt)
                )
            }

            Button {
                showResetConfirmation = true
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Reset Game".localized)
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundStyle(viewModel.currentSession.status == .ended ? Color.secondary : Color.Theme.primaryBlue)
                        Spacer()
                    }
                    if viewModel.currentSession.status == .ended {
                        Text("Reset is not available for ended trips.".localized)
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.isTripCreator || viewModel.currentSession.status == .ended)

            Divider()

            Button {
                showDeleteConfirmation = true
            } label: {
                HStack {
                    Text("Delete Trip".localized)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(.red)
                    Spacer()
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.isTripCreator)
        }
        .alert("End Trip".localized, isPresented: $showEndTripConfirmation) {
            Button("Cancel".localized, role: .cancel) {}
            Button("End Trip".localized, role: .destructive) {
                do {
                    try viewModel.endTrip()
                } catch {
                    viewModel.setError(error.localizedDescription)
                    retryAction = { try? viewModel.endTrip() }
                }
            }
        } message: {
            Text("This will stop the game. You won't be able to add states in this trip anymore.".localized)
        }
        .alert("Reset Game".localized, isPresented: $showResetConfirmation) {
            Button("Cancel".localized, role: .cancel) {}
            Button("Reset".localized, role: .destructive) {
                do {
                    try viewModel.resetTrip()
                } catch {
                    viewModel.setError(error.localizedDescription)
                    retryAction = { try? viewModel.resetTrip() }
                }
            }
        } message: {
            Text("Only this game's progress will be reset (discoveries and game state). The trip and its dates will not be changed.".localized)
        }
        .alert("Delete Trip".localized, isPresented: $showDeleteConfirmation) {
            Button("Cancel".localized, role: .cancel) {}
            Button("Delete".localized, role: .destructive) {
                do {
                    try viewModel.cancelTrip()
                    dismiss()
                } catch {
                    viewModel.setError(error.localizedDescription)
                    retryAction = {
                        try? viewModel.cancelTrip()
                        dismiss()
                    }
                }
            }
        } message: {
            Text("This will delete the trip and all scores will be removed.".localized)
        }
    }

    /// Enabled countries from current toggle state.
    private var selectedCountriesFromToggles: [PlateRegion.Country] {
        var list: [PlateRegion.Country] = []
        if includeUS { list.append(.unitedStates) }
        if includeCanada { list.append(.canada) }
        if includeMexico { list.append(.mexico) }
        return list
    }

    private var gameSettings: some View {
        Group {
            let canEditCountries = viewModel.currentSession.startedAt == nil && !game.commonConfig.configLocked

            VStack(alignment: .leading, spacing: 12) {
                Text("Countries to Include".localized)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .padding(.bottom, 4)

                CountryCheckboxRow(
                    title: "United States".localized,
                    isOn: Binding(
                        get: { includeUS },
                        set: { newValue in
                            includeUS = newValue
                            persistCountrySelection()
                        }
                    )
                )
                .disabled(!canEditCountries)
                .opacity(canEditCountries ? 1.0 : 0.5)

                CountryCheckboxRow(
                    title: "Canada".localized,
                    isOn: Binding(
                        get: { includeCanada },
                        set: { newValue in
                            includeCanada = newValue
                            persistCountrySelection()
                        }
                    )
                )
                .disabled(!canEditCountries)
                .opacity(canEditCountries ? 1.0 : 0.5)

                CountryCheckboxRow(
                    title: "Mexico".localized,
                    isOn: Binding(
                        get: { includeMexico },
                        set: { newValue in
                            includeMexico = newValue
                            persistCountrySelection()
                        }
                    )
                )
                .disabled(!canEditCountries)
                .opacity(canEditCountries ? 1.0 : 0.5)

                if selectedCountriesFromToggles.isEmpty {
                    Text("Select at least one country.".localized)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.red)
                        .accessibilityLabel("Select at least one country.".localized)
                }
            }
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

    private func syncCountryTogglesFromGameConfig() {
        let defaultConfig = LicensePlateGameConfig(
            selectedCountriesRawValues: [
                PlateRegion.Country.unitedStates.rawValue,
                PlateRegion.Country.canada.rawValue,
                PlateRegion.Country.mexico.rawValue
            ],
            territoryOptions: LicensePlateTerritoryOptions()
        )
        let selected = Set((game.licensePlateConfig() ?? defaultConfig).selectedCountries)
        includeUS = selected.contains(.unitedStates)
        includeCanada = selected.contains(.canada)
        includeMexico = selected.contains(.mexico)
    }

    private func persistCountrySelection() {
        viewModel.setEnabledCountriesForGame(selectedCountriesFromToggles)
    }
}

// Country checkbox row component for trip/game settings
private struct CountryCheckboxRow: View {
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
                .fill(Color.Theme.cardBackground)
        )
    }
}
