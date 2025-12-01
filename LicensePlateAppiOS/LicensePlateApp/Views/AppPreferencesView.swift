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
    @AppStorage("appDistanceUnit") private var appDistanceUnitRaw: String = AppDistanceUnit.miles.rawValue
    @AppStorage("appMapStyle") private var appMapStyleRaw: String = AppMapStyle.standard.rawValue
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.english.rawValue
    @AppStorage("appPlaySoundEffects") private var appPlaySoundEffects = true
    @AppStorage("appUseVibrations") private var appUseVibrations = true
    
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
    
    var body: some View {
        NavigationStack {
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
                            
                            // Hidden for now
                            if false {
                                SettingPickerRow(
                                    title: "Distance Unit",
                                    description: "Select miles or kilometers",
                                    selection: appDistanceUnit
                                )
                                
                                Divider()
                            }
                            
                            SettingPickerRow(
                                title: "Map Style",
                                description: "Choose standard or satellite view",
                                selection: appMapStyle
                            )
                          
                            Divider()
                            
                            // Hidden for now
                            if false {
                                SettingPickerRow(
                                    title: "Language",
                                    description: "Select your preferred language",
                                    selection: appLanguage
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

