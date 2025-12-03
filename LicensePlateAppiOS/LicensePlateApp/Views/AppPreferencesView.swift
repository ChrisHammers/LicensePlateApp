//
//  AppPreferencesView.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import SwiftUI

struct AppPreferencesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var systemColorScheme
    
    // App Preferences
    @AppStorage("appDarkMode") private var appDarkModeRaw: String = AppDarkMode.system.rawValue
    @AppStorage("appBackgroundStyle") private var appBackgroundStyleRaw: String = AppBackgroundStyle.none.rawValue
    @AppStorage("appDistanceUnit") private var appDistanceUnitRaw: String = AppDistanceUnit.miles.rawValue
    @AppStorage("appMapStyle") private var appMapStyleRaw: String = AppMapStyle.standard.rawValue
    @AppStorage("appShowRegionBorders") private var appShowRegionBorders = false
    @AppStorage("appShowMapMarkers") private var appShowMapMarkers = true
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.english.rawValue
    @AppStorage("appPlaySoundEffects") private var appPlaySoundEffects = true
    @AppStorage("appUseVibrations") private var appUseVibrations = true
    @AppStorage("appTripSortOrder") private var appTripSortOrderRaw: String = AppTripSortOrder.dateCreated.rawValue
    @AppStorage("appShowConfirmationDialogs") private var appShowConfirmationDialogs = true
    
    // Hidden preferences (for future use)
    @AppStorage("appFontSize") private var appFontSizeRaw: String = AppFontSize.medium.rawValue
    @AppStorage("appReduceMotion") private var appReduceMotion = false
    @AppStorage("appAutoSync") private var appAutoSync = true
    @AppStorage("appDefaultTab") private var appDefaultTabRaw: String = AppDefaultTab.trips.rawValue
    @AppStorage("appShowStatistics") private var appShowStatistics = true
    @AppStorage("appPlateDisplayFormat") private var appPlateDisplayFormatRaw: String = AppPlateDisplayFormat.fullName.rawValue
    @AppStorage("appMapDefaultZoom") private var appMapDefaultZoomRaw: String = AppMapDefaultZoom.medium.rawValue
    @AppStorage("appShowCompletedRegions") private var appShowCompletedRegions = true
    
    @State private var currentColorScheme: ColorScheme?
    
    // Computed properties for picker bindings
    private var appDarkMode: Binding<AppDarkMode> {
        Binding(
            get: { AppDarkMode(rawValue: appDarkModeRaw) ?? .system },
            set: { appDarkModeRaw = $0.rawValue }
        )
    }
    
    private var appBackgroundStyle: Binding<AppBackgroundStyle> {
        Binding(
            get: { AppBackgroundStyle(rawValue: appBackgroundStyleRaw) ?? .none },
            set: { appBackgroundStyleRaw = $0.rawValue }
        )
    }
    
    private var appDistanceUnit: Binding<AppDistanceUnit> {
        Binding(
            get: { AppDistanceUnit(rawValue: appDistanceUnitRaw) ?? .miles },
            set: { appDistanceUnitRaw = $0.rawValue }
        )
    }
    
    private var appMapStyle: Binding<AppMapStyle> {
        Binding(
            get: { AppMapStyle(rawValue: appMapStyleRaw) ?? .standard },
            set: { appMapStyleRaw = $0.rawValue }
        )
    }
    
    private var appLanguage: Binding<AppLanguage> {
        Binding(
            get: { AppLanguage(rawValue: appLanguageRaw) ?? .english },
            set: { appLanguageRaw = $0.rawValue }
        )
    }
    
    private var appTripSortOrder: Binding<AppTripSortOrder> {
        Binding(
            get: { AppTripSortOrder(rawValue: appTripSortOrderRaw) ?? .dateCreated },
            set: { appTripSortOrderRaw = $0.rawValue }
        )
    }
    
    // Hidden preference bindings
    private var appFontSize: Binding<AppFontSize> {
        Binding(
            get: { AppFontSize(rawValue: appFontSizeRaw) ?? .medium },
            set: { appFontSizeRaw = $0.rawValue }
        )
    }
    
    private var appDefaultTab: Binding<AppDefaultTab> {
        Binding(
            get: { AppDefaultTab(rawValue: appDefaultTabRaw) ?? .trips },
            set: { appDefaultTabRaw = $0.rawValue }
        )
    }
    
    private var appPlateDisplayFormat: Binding<AppPlateDisplayFormat> {
        Binding(
            get: { AppPlateDisplayFormat(rawValue: appPlateDisplayFormatRaw) ?? .fullName },
            set: { appPlateDisplayFormatRaw = $0.rawValue }
        )
    }
    
    private var appMapDefaultZoom: Binding<AppMapDefaultZoom> {
        Binding(
            get: { AppMapDefaultZoom(rawValue: appMapDefaultZoomRaw) ?? .medium },
            set: { appMapDefaultZoomRaw = $0.rawValue }
        )
    }
    
    var body: some View {
            ZStack {
                Color.Theme.background
                    .ignoresSafeArea()
                
                List {
                    Section {
                        VStack(spacing: 12) {
                            SettingPickerRow(
                                title: "Dark Mode",
                                description: "Choose your preferred appearance",
                                selection: appDarkMode
                            )
                          
                            Divider()
                            
                            SettingPickerRow(
                                title: "App Background",
                                description: "Choose background style",
                                selection: appBackgroundStyle
                            )
                            
                            Divider()
                            
                            SettingPickerRow(
                                title: "Distance Unit",
                                description: "Select miles or kilometers",
                                selection: appDistanceUnit
                            )
                            
                            Divider()
                            
                            SettingPickerRow(
                                title: "Map Style",
                                description: "Choose standard, satellite, or custom view optimized for region highlighting",
                                selection: appMapStyle
                            )
                            
                            Divider()
                            
                            SettingToggleRow(
                                title: "Show Region Borders",
                                description: "Display colored region boundaries on the map (blue for unfound, yellow for found)",
                                isOn: $appShowRegionBorders
                            )
                            
                            Divider()
                            
                            SettingToggleRow(
                                title: "Show Map Markers",
                                description: "Display markers on the map showing where regions were found (requires location data)",
                                isOn: $appShowMapMarkers
                            )
                          
                            Divider()
                            
                            SettingToggleRow(
                                title: "Play Sound Effects",
                                description: "Enable audio feedback for app interactions",
                                isOn: $appPlaySoundEffects
                            )
                            
                            SettingToggleRow(
                                title: "Use Vibrations",
                                description: "Enable haptic feedback",
                                isOn: $appUseVibrations
                            )
                            
                            // Hidden preferences (for future use)
                            if false {
                                Divider()
                                
                                SettingPickerRow(
                                    title: "Trip Sort Order",
                                    description: "How to sort trips in the list",
                                    selection: appTripSortOrder
                                )
                                
                                Divider()
                                
                                SettingToggleRow(
                                    title: "Show Confirmation Dialogs",
                                    description: "Show confirmation prompts for destructive actions like deleting trips",
                                    isOn: $appShowConfirmationDialogs
                                )
                                
                                Divider()
                                Divider()
                                
                                SettingPickerRow(
                                    title: "Language",
                                    description: "Select your preferred language",
                                    selection: appLanguage
                                )
                              
                                Divider()
                                
                                SettingPickerRow(
                                    title: "Font Size",
                                    description: "Adjust text size for better readability",
                                    selection: appFontSize
                                )
                                
                                Divider()
                                
                                SettingToggleRow(
                                    title: "Reduce Motion",
                                    description: "Respect iOS Reduce Motion setting",
                                    isOn: $appReduceMotion
                                )
                                
                                Divider()
                                
                                SettingToggleRow(
                                    title: "Auto-Sync",
                                    description: "Automatically sync data to cloud",
                                    isOn: $appAutoSync
                                )
                                
                                Divider()
                                
                                SettingPickerRow(
                                    title: "Default Tab",
                                    description: "Which tab to show when opening the app",
                                    selection: appDefaultTab
                                )
                                
                                Divider()
                                
                                SettingToggleRow(
                                    title: "Show Statistics",
                                    description: "Display statistics on the main screen",
                                    isOn: $appShowStatistics
                                )
                                
                                Divider()
                                
                                SettingPickerRow(
                                    title: "Plate Display Format",
                                    description: "How to display license plate regions",
                                    selection: appPlateDisplayFormat
                                )
                                
                                Divider()
                                
                                SettingPickerRow(
                                    title: "Map Default Zoom",
                                    description: "Default zoom level when opening maps",
                                    selection: appMapDefaultZoom
                                )
                                
                                Divider()
                                
                                SettingToggleRow(
                                    title: "Show Completed Regions",
                                    description: "Display regions that are already found in lists",
                                    isOn: $appShowCompletedRegions
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
                    .textCase(nil)
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("App Preferences")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .accessibilityLabel("Done")
                    .accessibilityHint("Closes this view")
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
    }
    
    private func updateColorScheme() {
        let darkMode = AppDarkMode(rawValue: appDarkModeRaw) ?? .system
        switch darkMode {
        case .light:
            currentColorScheme = .light
        case .dark:
            currentColorScheme = .dark
        case .system:
            currentColorScheme = systemColorScheme
        }
    }
}

