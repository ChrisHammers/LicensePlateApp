//
//  NewTripDefaultsView.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import SwiftUI

struct NewTripDefaultsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = NewTripDefaultsViewModel()

    var body: some View {
        AppBackgroundView {
            List {
                Section("Trip Defaults") {
                    VStack(spacing: 12) {
                        // Start Trip - First item
                        SettingToggleRow(
                            title: "Start Trip right away".localized,
                            description: "Automatically start new trips when created".localized,
                            isOn: $viewModel.startTripRightAway
                        )
                        
                        Divider()
                        
                        // Tracking Options
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Location Tracking".localized)
                                .font(.system(.headline, design: .rounded))
                                .foregroundStyle(Color.Theme.primaryBlue)
                                .padding(.bottom, 4)
                                .accessibilityAddTraits(.isHeader)
                            
                            SettingToggleRow(
                                title: "Save location when marking plates".localized,
                                description: "Store location data when marking plates (default for new trips)".localized,
                                isOn: $viewModel.saveLocationWhenMarkingPlates
                            )
                            
                            SettingToggleRow(
                                title: "Show my location on large map".localized,
                                description: "Display current location on full-screen map (default for new trips)".localized,
                                isOn: $viewModel.showMyLocationOnLargeMap
                            )
                            
                            SettingToggleRow(
                                title: "Track my location during trip".localized,
                                description: "Continuously track location while trip is active (default for new trips)".localized,
                                isOn: $viewModel.trackMyLocationDuringTrip
                            )
                            
                            SettingToggleRow(
                                title: "Show my active trip on the large map".localized,
                                description: "Display active trip on full-screen map (default for new trips)".localized,
                                isOn: $viewModel.showMyActiveTripOnLargeMap
                            )
                            .disabled(!viewModel.trackMyLocationDuringTrip)
                            .opacity(viewModel.trackMyLocationDuringTrip ? 1.0 : 0.5)
                            .accessibilityHintWhenDisabled(
                                !viewModel.trackMyLocationDuringTrip,
                                hint: "Enable location tracking during trip first".localized
                            )
                            
                            SettingToggleRow(
                                title: "Show my active trip on the small map".localized,
                                description: "Display active trip on small map (default for new trips)".localized,
                                isOn: $viewModel.showMyActiveTripOnSmallMap
                            )
                            .disabled(!viewModel.trackMyLocationDuringTrip)
                            .opacity(viewModel.trackMyLocationDuringTrip ? 1.0 : 0.5)
                            .accessibilityHintWhenDisabled(
                                !viewModel.trackMyLocationDuringTrip,
                                hint: "Enable location tracking during trip first".localized
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .background(Color.Theme.cardBackground)
                    .cornerRadius(20)
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                    .listRowBackground(Color.clear)
                }
                
                Section("Game Defaults") {
                    VStack(spacing: 12) {
                        // Countries
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Default Countries".localized)
                                .font(.system(.headline, design: .rounded))
                                .foregroundStyle(Color.Theme.primaryBlue)
                                .accessibilityAddTraits(.isHeader)
                            
                            Text("Select which countries' license plates will be included by default when creating new trips".localized)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(Color.Theme.softBrown)
                                .padding(.bottom, 4)
                                .padding(.horizontal, 16)
                            
                            SettingToggleRow(title: "United States".localized, isOn: $viewModel.includeUS)
                            SettingToggleRow(title: "Canada".localized, isOn: $viewModel.includeCanada)
                            SettingToggleRow(title: "Mexico".localized, isOn: $viewModel.includeMexico)
                            
                            if let message = viewModel.countryValidationMessage {
                                Text(message)
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(Color.red)
                                    .accessibilityLabel(message)
                            }
                        }
                        
                        Divider()
                        
                        // Voice Settings
                        SettingToggleRow(
                            title: "Skip Voice Confirmation".localized,
                            description: "Automatically add license plates heard by speech recognition without requiring user confirmation. This is the default for NEW trips created, this can be changed per trip as well.".localized,
                            isOn: $viewModel.skipVoiceConfirmation
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .background(Color.Theme.cardBackground)
                    .cornerRadius(20)
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                    .listRowBackground(Color.clear)
                }
                .textCase(nil)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("New Trip Defaults".localized)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done".localized) {
                    viewModel.save()
                    dismiss()
                }
                .font(.system(.body, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(!viewModel.canSave ? .secondary : Color.Theme.primaryBlue)
                .disabled(!viewModel.canSave)
                .accessibilityLabel("Done".localized)
                .accessibilityHint(
                    !viewModel.canSave
                        ? "Select at least one country before saving.".localized
                        : "Saves new trip defaults and closes this view".localized
                )
            }
        }
        .onAppear {
            viewModel.reloadFromStore()
        }
    }
}

private extension View {
    @ViewBuilder
    func accessibilityHintWhenDisabled(_ isDisabled: Bool, hint: String) -> some View {
        if isDisabled {
            self.accessibilityHint(hint)
        } else {
            self
        }
    }
}
