//
//  TripSetupView.swift
//  LicensePlateApp
//
//  Step 1 of new-trip flow: trip name, passengers, and trip settings.
//

import SwiftUI

struct TripSetupView: View {
    @ObservedObject var viewModel: TripSetupViewModel
    var onNext: () -> Void
    var onCancel: () -> Void

    @State private var isShowingPassengerSelector = false
    @EnvironmentObject private var authService: FirebaseAuthService

    @AppStorage("appPlaySoundEffects") private var appPlaySoundEffects = true
    @AppStorage("appUseVibrations") private var appUseVibrations = true

    var body: some View {
        AppBackgroundView {
            List {
                if viewModel.shouldShowSetupAd {
                    adSection
                }
                basicInfoSection
                tripParticipationSection
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
                    onCancel()
                }
                .foregroundStyle(Color.Theme.primaryBlue)
                .accessibilityLabel("Cancel".localized)
                .accessibilityHint("Cancels creating a new trip".localized)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Next".localized) {
                    FeedbackService.shared.buttonTap()
                    onNext()
                }
                .fontWeight(.semibold)
                .foregroundStyle(Color.Theme.primaryBlue)
                .accessibilityLabel("Next".localized)
                .accessibilityHint("Continues to game setup".localized)
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

    private var tripOptionsSection: some View {
        Section {
            VStack(spacing: 12) {
                SettingToggleRow(
                    title: "Start Trip right away".localized,
                    description: "Automatically start the trip when created".localized,
                    isOn: $viewModel.startTripRightAway
                )
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
            AdBannerView(surface: .tripSetup)
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                .listRowBackground(Color.clear)
        }
        .textCase(nil)
    }
}

#Preview("Trip Setup") {
    let auth = FirebaseAuthService()
    auth.currentUser = AppUser(id: "preview-user", userName: "Preview", firebaseUID: "preview-user")
    return NavigationStack {
        TripSetupView(
            viewModel: TripSetupViewModel(authService: auth),
            onNext: {},
            onCancel: {}
        )
    }
    .environmentObject(auth)
}
