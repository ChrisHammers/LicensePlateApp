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
    @EnvironmentObject var authService: FirebaseAuthService
    @EnvironmentObject var syncService: FirebaseTripSyncService
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    // App Preferences
    @AppStorage("appDarkMode") private var appDarkModeRaw: String = AppDarkMode.system.rawValue
    @AppStorage("appDistanceUnit") private var appDistanceUnitRaw: String = AppDistanceUnit.miles.rawValue
    @AppStorage("appMapStyle") private var appMapStyleRaw: String = AppMapStyle.standard.rawValue
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
                                title: "Distance Unit",
                                description: "Select miles or kilometers",
                                selection: appDistanceUnit
                            )
                            
                            Divider()
                            
                            SettingPickerRow(
                                title: "Map Style",
                                description: "Choose standard or satellite view",
                                selection: appMapStyle
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
                            
                            // Cloud Sync section (only visible when authenticated)
                            if authService.isTrulyAuthenticated {
                                Divider()
                                
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text("Cloud Sync")
                                            .font(.system(.body, design: .rounded))
                                            .fontWeight(.semibold)
                                            .foregroundStyle(Color.Theme.primaryBlue)
                                        
                                        Spacer()
                                        
                                        if syncService.isSyncing {
                                            ProgressView()
                                                .scaleEffect(0.8)
                                        } else if syncService.isSyncEnabled {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(Color.green)
                                        } else {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(Color.red)
                                        }
                                    }
                                    
                                    if let lastSync = syncService.lastSyncTime {
                                        Text("Last synced: \(dateFormatter.string(from: lastSync))")
                                            .font(.system(.caption, design: .rounded))
                                            .foregroundStyle(Color.Theme.softBrown)
                                    } else if syncService.isSyncEnabled {
                                        Text("Never synced")
                                            .font(.system(.caption, design: .rounded))
                                            .foregroundStyle(Color.Theme.softBrown)
                                    } else {
                                        Text("Sign in to enable cloud sync")
                                            .font(.system(.caption, design: .rounded))
                                            .foregroundStyle(Color.Theme.softBrown)
                                    }
                                    
                                    if let error = syncService.syncError {
                                        Text("Error: \(error)")
                                            .font(.system(.caption, design: .rounded))
                                            .foregroundStyle(Color.red)
                                    }
                                    
                                    Button {
                                        Task {
                                            await syncService.syncAllTrips()
                                        }
                                    } label: {
                                        HStack {
                                            Image(systemName: "arrow.clockwise")
                                            Text("Sync Now")
                                        }
                                        .font(.system(.subheadline, design: .rounded))
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Color.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(
                                            Capsule()
                                                .fill(Color.Theme.primaryBlue)
                                        )
                                    }
                                    .disabled(syncService.isSyncing || !syncService.isSyncEnabled)
                                    .opacity((syncService.isSyncing || !syncService.isSyncEnabled) ? 0.5 : 1.0)
                                }
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .fill(Color.Theme.cardBackground)
                                )
                            }
                            
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

