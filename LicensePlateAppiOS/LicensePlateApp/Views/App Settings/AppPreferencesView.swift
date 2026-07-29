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
  @EnvironmentObject private var authService: FirebaseAuthService

  // App Preferences
  @AppStorage("appDarkMode") private var appDarkModeRaw: String = AppDarkMode.system.rawValue
  @AppStorage("appBackgroundStyle") private var appBackgroundStyleRaw: String = AppBackgroundStyle.paths.rawValue
  // TODO(cloud-prefs): re-enable when wired — no production distance formatting consumer.
  // @AppStorage("appDistanceUnit") private var appDistanceUnitRaw: String = AppDistanceUnit.miles.rawValue
  @AppStorage("appMapStyle") private var appMapStyleRaw: String = AppMapStyle.standard.rawValue
  @AppStorage("appShowRegionBorders") private var appShowRegionBorders = false
  @AppStorage("appShowMapMarkers") private var appShowMapMarkers = true
  @AppStorage("appShowUserAvatarOnMap") private var appShowUserAvatarOnMap = false
  @AppStorage("useGMURendering") private var useGMURendering = false // For comparison testing
  @AppStorage("useTileOverlayRendering") private var useTileOverlayRendering = false // For performance testing
  @AppStorage("appPlaySoundEffects") private var appPlaySoundEffects = true
  @AppStorage("appUseVibrations") private var appUseVibrations = true
  @AppStorage("appMapProvider") private var appMapProviderRaw: String = AppPreferences.defaultMapProvider().rawValue

  @StateObject private var notificationSettings = NotificationSettingsViewModel()
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
  
  // TODO(cloud-prefs): re-enable when wired — no production distance formatting consumer.
  // private var appDistanceUnit: Binding<AppDistanceUnit> {
  //   Binding(
  //     get: { AppDistanceUnit(rawValue: appDistanceUnitRaw) ?? .miles },
  //     set: { appDistanceUnitRaw = $0.rawValue }
  //   )
  // }
  
  private var appMapStyle: Binding<AppMapStyle> {
    Binding(
      get: { AppMapStyle(rawValue: appMapStyleRaw) ?? .standard },
      set: { appMapStyleRaw = $0.rawValue }
    )
  }
  
  private var appMapProvider: Binding<AppMapProvider> {
    Binding(
      get: { AppMapProvider(rawValue: appMapProviderRaw) ?? AppPreferences.defaultMapProvider() },
      set: { appMapProviderRaw = $0.rawValue }
    )
  }
  
  var body: some View {
    AppBackgroundView {
      List {
        Section {
          VStack(spacing: 12) {
            SettingPickerRow(
              title: "Dark Mode".localized,
              description: "Choose your preferred appearance".localized,
              selection: appDarkMode
            )
            
            Divider()
            
            SettingPickerRow(
              title: "App Background".localized,
              description: "Choose background style".localized,
              selection: appBackgroundStyle
            )
            
            Divider()
            
            // TODO(cloud-prefs): re-enable when wired — no production distance formatting consumer.
            // SettingPickerRow(
            //   title: "Distance Unit".localized,
            //   description: "Select miles or kilometers".localized,
            //   selection: appDistanceUnit
            // )
            //
            // Divider()
            
            SettingPickerRow(
              title: "Map Style".localized,
              description: "Choose standard or satellite view".localized,
              selection: appMapStyle
            )
            
            Divider()
            
            SettingToggleRow(
              title: "Show Map Markers".localized,
              description: "Display markers on the map showing where regions were found (requires location data)".localized,
              isOn: $appShowMapMarkers
            )
            
            Divider()
            
            SettingToggleRow(
              title: "Show Avatars on Map".localized,
              description: "Show avatars at your location on the live map (green circle remains)".localized,
              isOn: $appShowUserAvatarOnMap
            )
            
            Divider()
            
            SettingToggleRow(
              title: "Play Sound Effects".localized,
              description: "Enable audio feedback for app interactions".localized,
              isOn: $appPlaySoundEffects
            )
            
            SettingToggleRow(
              title: "Use Vibrations".localized,
              description: "Enable haptic feedback".localized,
              isOn: $appUseVibrations
            )

            Divider()

            SettingToggleRow(
              title: "return_streak.settings.reminder.title".localized,
              description: "return_streak.settings.reminder.detail".localized,
              isOn: $notificationSettings.returnStreakReminder
            )
            .onChange(of: notificationSettings.returnStreakReminder) { _, _ in
              Task { await notificationSettings.persistFromUI() }
            }
            .accessibilityLabel("return_streak.settings.reminder.title".localized)
            .accessibilityHint("return_streak.settings.reminder.detail".localized)
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 16)
          .background(Color.Theme.cardBackground)
          .cornerRadius(20)
          .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
          .listRowBackground(Color.clear)
        }
        .textCase(nil)
        
#if DEBUG
        Section {
          VStack(spacing: 12) {
            SettingPickerRow(
              title: "Map Provider".localized,
              description: "Choose between Apple Maps and Google Maps (DEBUG only)".localized,
              selection: appMapProvider
            )
            
            Divider()
            
            SettingToggleRow(
              title: "Show Region Borders".localized,
              description: "Display colored region boundaries on the map (blue for unfound, yellow for found)".localized,
              isOn: $appShowRegionBorders
            )
            
            Divider()
            
            SettingToggleRow(
              title: "Use GMU Rendering (Testing)".localized,
              description: "Use Google Maps Utils for polygon rendering (for performance comparison)".localized,
              isOn: $useGMURendering
            )
            
            Divider()
            
            SettingToggleRow(
              title: "Use Tile Overlay (Testing)".localized,
              description: "Use TileOverlay for polygon rendering - best performance for many polygons".localized,
              isOn: $useTileOverlayRendering
            )

            Divider()

            XpProgressionDebugExportButton(
              userId: XpProgressionDebugExporter.resolvedUserIdFromProgressionRepository()
            )
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 16)
          .background(Color.Theme.cardBackground)
          .cornerRadius(20)
          .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
          .listRowBackground(Color.clear)
        } header: {
          Text("Debug Settings".localized)
            .font(.system(.headline, design: .rounded))
            .foregroundStyle(Color.Theme.primaryBlue)
        }
        .textCase(nil)
#endif
      }
      .listStyle(.insetGrouped)
      .scrollContentBackground(.hidden)
    }
    .navigationTitle("App Preferences".localized)
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
    .preferredColorScheme(currentColorScheme)
    .onAppear {
      updateColorScheme()
      let userId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id
      notificationSettings.configure(userId: userId)
      Task { await notificationSettings.loadIfNeeded() }
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
