//
//  NewTripDefaultsView.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import SwiftUI

struct NewTripDefaultsView: View {
    @Environment(\.dismiss) private var dismiss
    
    // New Trip Defaults
    @AppStorage("defaultIncludeUS") private var defaultIncludeUS = true
    @AppStorage("defaultIncludeCanada") private var defaultIncludeCanada = true
    @AppStorage("defaultIncludeMexico") private var defaultIncludeMexico = true
    @AppStorage("defaultStartTripRightAway") private var defaultStartTripRightAway = false
    @AppStorage("defaultSkipVoiceConfirmation") private var defaultSkipVoiceConfirmation = false
    @AppStorage("defaultHoldToTalk") private var defaultHoldToTalk = true
    @AppStorage("defaultSaveLocationWhenMarkingPlates") private var defaultSaveLocationWhenMarkingPlates = true
    @AppStorage("defaultShowMyLocationOnLargeMap") private var defaultShowMyLocationOnLargeMap = true
    @AppStorage("defaultTrackMyLocationDuringTrip") private var defaultTrackMyLocationDuringTrip = true
    @AppStorage("defaultShowMyActiveTripOnLargeMap") private var defaultShowMyActiveTripOnLargeMap = true
    @AppStorage("defaultShowMyActiveTripOnSmallMap") private var defaultShowMyActiveTripOnSmallMap = true
    
    var body: some View {
            ZStack {
                Color.Theme.background
                    .ignoresSafeArea()
                
                List {
                    Section {
                        VStack(spacing: 12) {
                            // Start Trip - First item
                            SettingToggleRow(
                                title: "Start Trip right away".localized,
                                description: "Automatically start new trips when created".localized,
                                isOn: $defaultStartTripRightAway
                            )
                            
                            Divider()
                            
                            // Countries
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Default Countries".localized)
                                    .font(.system(.headline, design: .rounded))
                                    .foregroundStyle(Color.Theme.primaryBlue)
                                
                                Text("Select which countries' license plates will be included by default when creating new trips".localized)
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(Color.Theme.softBrown)
                                    .padding(.bottom, 4)
                                
                                CountryCheckboxRow(title: "United States".localized, isOn: $defaultIncludeUS)
                                CountryCheckboxRow(title: "Canada".localized, isOn: $defaultIncludeCanada)
                                CountryCheckboxRow(title: "Mexico".localized, isOn: $defaultIncludeMexico)
                            }
                            
                            Divider()
                            
                            // Voice Settings
                            SettingToggleRow(
                                title: "Skip Voice Confirmation".localized,
                                description: "Automatically add license plates heard by speech recognition without requiring user confirmation. This is the default for NEW trips created, this can be changed per trip as well.".localized,
                                isOn: $defaultSkipVoiceConfirmation
                            )
                            
                            Divider()
                            
                            // Tracking Options
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Location Tracking".localized)
                                    .font(.system(.headline, design: .rounded))
                                    .foregroundStyle(Color.Theme.primaryBlue)
                                    .padding(.bottom, 4)
                                
                                SettingToggleRow(
                                    title: "Save location when marking plates".localized,
                                    description: "Store location data when marking plates (default for new trips)".localized,
                                    isOn: $defaultSaveLocationWhenMarkingPlates
                                )
                                
                                SettingToggleRow(
                                    title: "Show my location on large map".localized,
                                    description: "Display current location on full-screen map (default for new trips)".localized,
                                    isOn: $defaultShowMyLocationOnLargeMap
                                )
                                
                                SettingToggleRow(
                                    title: "Track my location during trip".localized,
                                    description: "Continuously track location while trip is active (default for new trips)".localized,
                                    isOn: $defaultTrackMyLocationDuringTrip
                                )
                                
                                SettingToggleRow(
                                    title: "Show my active trip on the large map".localized,
                                    description: "Display active trip on full-screen map (default for new trips)".localized,
                                    isOn: $defaultShowMyActiveTripOnLargeMap
                                )
                                .disabled(!defaultTrackMyLocationDuringTrip)
                                .opacity(defaultTrackMyLocationDuringTrip ? 1.0 : 0.5)
                                
                                SettingToggleRow(
                                    title: "Show my active trip on the small map".localized,
                                    description: "Display active trip on small map (default for new trips)".localized,
                                    isOn: $defaultShowMyActiveTripOnSmallMap
                                )
                                .disabled(!defaultTrackMyLocationDuringTrip)
                                .opacity(defaultTrackMyLocationDuringTrip ? 1.0 : 0.5)
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
                        dismiss()
                    }
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .accessibilityLabel("Done".localized)
                    .accessibilityHint("Closes this view".localized)
                }
            }
    }
}

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

