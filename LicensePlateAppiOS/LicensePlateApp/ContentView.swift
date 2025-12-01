//
//  ContentView.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import SwiftUI
import SwiftData
import MapKit
import CoreLocation
import AVFoundation
import UserNotifications
import Speech

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Trip.createdAt, order: .reverse) private var trips: [Trip]
    @EnvironmentObject var authService: FirebaseAuthService
    @State private var path: [UUID] = []
    @State private var isShowingCreateSheet = false
    @State private var isShowingSettings = false
    
    // Custom detent for the new trip sheet - small enough to show only Basic Info
    private let smallDetent = PresentationDetent.fraction(0.25)
    @State private var sheetDetent: PresentationDetent = .fraction(0.25)
    
    // App Preferences
    @AppStorage("appDarkMode") private var appDarkModeRaw: String = AppDarkMode.system.rawValue
    
    // Computed property for color scheme
    private var currentColorScheme: ColorScheme? {
        AppPreferences.colorSchemeFromPreference(rawValue: appDarkModeRaw)
    }

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

  init() {
    UINavigationBar.appearance().titleTextAttributes = [.foregroundColor: Color.Theme.primaryBlue.uiColor]

     }
    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color.Theme.background
                    .ignoresSafeArea()

                List {
                    Section {
                        header
                            .listRowInsets(.init(top: 24, leading: 20, bottom: 24, trailing: 20))
                            .listRowBackground(Color.clear)
                    }
                    .textCase(nil)

                    if trips.isEmpty {
                        Section {
                            emptyState
                                .listRowInsets(.init(top: 0, leading: 20, bottom: 24, trailing: 20))
                                .listRowBackground(Color.clear)
                        }
                        .textCase(nil)
                    } else {
                        Section("Trips") {
                            tripList
                        }
                        .textCase(nil)
                        .listRowBackground(Color.clear)
                    }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
            }
            .navigationTitle("RoadTrip Royale")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundStyle(Color.Theme.primaryBlue)
                    }
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                DefaultSettingsView()
                    .environmentObject(authService)
            }
            .task {
                // Initialize authentication state (checks Firebase Auth first, then local)
                await authService.initializeAuthState(modelContext: modelContext)
            }
            .overlay {
                if authService.showUsernameConflictDialog {
                    UsernameConflictDialog(authService: authService)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                addTripButton
            }
            .sheet(isPresented: $isShowingCreateSheet) {
                NewTripSheet { tripData in
                    createTrip(with: tripData)
                }
                .presentationDetents([smallDetent, .medium, .large], selection: $sheetDetent)
                .presentationDragIndicator(.visible)
                .onAppear {
                    sheetDetent = smallDetent
                }
            }
            .navigationDestination(for: UUID.self) { tripID in
                if let trip = trips.first(where: { $0.id == tripID }) {
                    TripTrackerView(trip: trip)
                } else {
                    TripMissingView()
                }
            }
        }
        .preferredColorScheme(currentColorScheme)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RoadTrip Royale")
                .font(.system(.largeTitle, design: .rounded))
                .fontWeight(.bold)
                .foregroundStyle(Color.Theme.primaryBlue)
                .shadow(color: Color.Theme.primaryBlue.opacity(0.5), radius: 5)
            
            Text("Spot license plates, conquer the map, and rule the open road!")
                .font(.system(.title2, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(Color.Theme.primaryBlue.opacity(0.8))

            Text("Track every plate you see across the United States, Canada, and Mexico.")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "car.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.Theme.accentYellow)

            Text("No trips yet")
                .font(.system(.title2, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(Color.Theme.primaryBlue)

            Text("Start your first adventure and begin collecting plates from across North America.")
                .multilineTextAlignment(.center)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
                .padding(.horizontal)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.Theme.cardBackground)
        )
    }

    private var tripList: some View {
        ForEach(trips) { trip in
            NavigationLink(value: trip.id) {
                TripRow(trip: trip)
                    .padding(.vertical, 8)
            }
            .listRowInsets(.init(top: 6, leading: 20, bottom: 6, trailing: 20))
            .listRowBackground(Color.clear)
        }
        .onDelete(perform: deleteTrips)
    }

    private var addTripButton: some View {
        Button {
            isShowingCreateSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24, weight: .bold))
                Text("Create Trip")
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                Capsule()
                    .fill(Color.Theme.primaryBlue)
            )
            .foregroundStyle(Color.white)
            .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
        }
        .padding(.trailing, 20)
        .padding(.bottom, 32)
    }

    @AppStorage("defaultSkipVoiceConfirmation") private var defaultSkipVoiceConfirmation = false
    @AppStorage("defaultHoldToTalk") private var defaultHoldToTalk = true
    @AppStorage("defaultStartTripRightAway") private var defaultStartTripRightAway = false
    @AppStorage("defaultIncludeUS") private var defaultIncludeUS = true
    @AppStorage("defaultIncludeCanada") private var defaultIncludeCanada = true
    @AppStorage("defaultIncludeMexico") private var defaultIncludeMexico = true
    @AppStorage("defaultSaveLocationWhenMarkingPlates") private var defaultSaveLocationWhenMarkingPlates = true
    @AppStorage("defaultShowMyLocationOnLargeMap") private var defaultShowMyLocationOnLargeMap = true
    @AppStorage("defaultTrackMyLocationDuringTrip") private var defaultTrackMyLocationDuringTrip = true
    @AppStorage("defaultShowMyActiveTripOnLargeMap") private var defaultShowMyActiveTripOnLargeMap = true
    @AppStorage("defaultShowMyActiveTripOnSmallMap") private var defaultShowMyActiveTripOnSmallMap = true
    
    struct TripCreationData {
        let name: String?
        let enabledCountries: [PlateRegion.Country]
        let startTripRightAway: Bool
        let skipVoiceConfirmation: Bool
        let holdToTalk: Bool
        let saveLocationWhenMarkingPlates: Bool
        let showMyLocationOnLargeMap: Bool
        let trackMyLocationDuringTrip: Bool
        let showMyActiveTripOnLargeMap: Bool
        let showMyActiveTripOnSmallMap: Bool
    }
    
    private func createTrip(with data: TripCreationData) {
        let finalName: String
        let createdAt = Date()

        if let name = data.name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            finalName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            finalName = dateFormatter.string(from: createdAt)
        }

        let newTrip = Trip(
            createdAt: createdAt,
            name: finalName,
            foundRegions: [],
            skipVoiceConfirmation: data.skipVoiceConfirmation,
            holdToTalk: data.holdToTalk,
            createdBy: authService.currentUser?.id,
            startedAt: data.startTripRightAway ? createdAt : nil,
            saveLocationWhenMarkingPlates: data.saveLocationWhenMarkingPlates, showMyLocationOnLargeMap: data.showMyLocationOnLargeMap,
            trackMyLocationDuringTrip: data.trackMyLocationDuringTrip,
            showMyActiveTripOnLargeMap: data.showMyActiveTripOnLargeMap,
            showMyActiveTripOnSmallMap: data.showMyActiveTripOnSmallMap,
            enabledCountries: data.enabledCountries
        )

        modelContext.insert(newTrip)

        do {
            try modelContext.save()
        } catch {
            // In a production app, handle the error appropriately.
            assertionFailure("Failed to save new trip: \(error)")
        }

        path.append(newTrip.id)
    }

    private func deleteTrips(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(trips[index])
        }
        do {
            try modelContext.save()
        } catch {
            assertionFailure("Failed to delete trip: \(error)")
        }
    }
}

private struct NewTripSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tripName: String = ""
    
    // Defaults from AppStorage
    @AppStorage("defaultSkipVoiceConfirmation") private var defaultSkipVoiceConfirmation = false
    @AppStorage("defaultHoldToTalk") private var defaultHoldToTalk = true
    @AppStorage("defaultStartTripRightAway") private var defaultStartTripRightAway = false
    @AppStorage("defaultIncludeUS") private var defaultIncludeUS = true
    @AppStorage("defaultIncludeCanada") private var defaultIncludeCanada = true
    @AppStorage("defaultIncludeMexico") private var defaultIncludeMexico = true
    @AppStorage("defaultSaveLocationWhenMarkingPlates") private var defaultSaveLocationWhenMarkingPlates = true
    @AppStorage("defaultShowMyLocationOnLargeMap") private var defaultShowMyLocationOnLargeMap = true
    @AppStorage("defaultTrackMyLocationDuringTrip") private var defaultTrackMyLocationDuringTrip = true
    @AppStorage("defaultShowMyActiveTripOnLargeMap") private var defaultShowMyActiveTripOnLargeMap = true
    @AppStorage("defaultShowMyActiveTripOnSmallMap") private var defaultShowMyActiveTripOnSmallMap = true
    
    // Trip settings state
    @State private var includeUS: Bool
    @State private var includeCanada: Bool
    @State private var includeMexico: Bool
    @State private var startTripRightAway: Bool
    @State private var skipVoiceConfirmation: Bool
    @State private var holdToTalk: Bool
    @State private var saveLocationWhenMarkingPlates: Bool
    @State private var showMyLocationOnLargeMap: Bool
    @State private var trackMyLocationDuringTrip: Bool
    @State private var showMyActiveTripOnLargeMap: Bool
    @State private var showMyActiveTripOnSmallMap: Bool
    
    var onCreate: (ContentView.TripCreationData) -> Void
    
    init(onCreate: @escaping (ContentView.TripCreationData) -> Void) {
        self.onCreate = onCreate
        
        // Initialize with defaults
        _includeUS = State(initialValue: UserDefaults.standard.bool(forKey: "defaultIncludeUS") ? true : true)
        _includeCanada = State(initialValue: UserDefaults.standard.bool(forKey: "defaultIncludeCanada") ? true : true)
        _includeMexico = State(initialValue: UserDefaults.standard.bool(forKey: "defaultIncludeMexico") ? true : true)
        _startTripRightAway = State(initialValue: UserDefaults.standard.bool(forKey: "defaultStartTripRightAway"))
        _skipVoiceConfirmation = State(initialValue: UserDefaults.standard.bool(forKey: "defaultSkipVoiceConfirmation"))
        _holdToTalk = State(initialValue: UserDefaults.standard.object(forKey: "defaultHoldToTalk") as? Bool ?? true)
        _saveLocationWhenMarkingPlates = State(initialValue: UserDefaults.standard.object(forKey: "defaultSaveLocationWhenMarkingPlates") as? Bool ?? true)
        _showMyLocationOnLargeMap = State(initialValue: UserDefaults.standard.object(forKey: "defaultShowMyLocationOnLargeMap") as? Bool ?? true)
        _trackMyLocationDuringTrip = State(initialValue: UserDefaults.standard.object(forKey: "defaultTrackMyLocationDuringTrip") as? Bool ?? true)
        _showMyActiveTripOnLargeMap = State(initialValue: UserDefaults.standard.object(forKey: "defaultShowMyActiveTripOnLargeMap") as? Bool ?? true)
        _showMyActiveTripOnSmallMap = State(initialValue: UserDefaults.standard.object(forKey: "defaultShowMyActiveTripOnSmallMap") as? Bool ?? true)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.Theme.background
                    .ignoresSafeArea()
                
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Trip Name")
                                .font(.system(.headline, design: .rounded))
                                .foregroundStyle(Color.Theme.primaryBlue)
                            
                            TextField("Automatically use date & time", text: $tripName)
                                .textInputAutocapitalization(.words)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.Theme.background)
                                )
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .background(Color.Theme.cardBackground)
                        .cornerRadius(20)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                        .listRowBackground(Color.clear)
                    } header: {
                        Text("Basic Info")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(Color.Theme.primaryBlue)
                    }
                    .textCase(nil)
                    
                    Section {
                        VStack(spacing: 12) {
                            // Start Trip
                            SettingToggleRow(
                                title: "Start Trip right away",
                                description: "Automatically start the trip when created",
                                isOn: $startTripRightAway
                            )
                            
                            Divider()
                            
                            // Countries
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Countries to Include")
                                    .font(.system(.headline, design: .rounded))
                                    .foregroundStyle(Color.Theme.primaryBlue)
                                
                                CountryCheckboxRow(title: "United States", isOn: $includeUS)
                                CountryCheckboxRow(title: "Canada", isOn: $includeCanada)
                                CountryCheckboxRow(title: "Mexico", isOn: $includeMexico)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .background(Color.Theme.cardBackground)
                        .cornerRadius(20)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                        .listRowBackground(Color.clear)
                    } header: {
                        Text("Trip Options")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(Color.Theme.primaryBlue)
                    }
                    .textCase(nil)
                    
                    Section {
                        VStack(spacing: 12) {
                            // Voice Settings
                            SettingToggleRow(
                                title: "Skip Voice Confirmation",
                                description: "Automatically add license plates without confirmation when using Voice",
                                isOn: $skipVoiceConfirmation
                            )
                            
                            Divider()
                            
                            // Location Settings
                            SettingToggleRow(
                                title: "Save location when marking plates",
                                description: "Store location data when you mark a plate as found",
                                isOn: $saveLocationWhenMarkingPlates
                            )
                            
                            Divider()
                            
                            SettingToggleRow(
                                title: "Show my location on large map",
                                description: "Display your current location on the full-screen map",
                                isOn: $showMyLocationOnLargeMap
                            )
                            
                            Divider()
                            
                            SettingToggleRow(
                                title: "Track my location during trip",
                                description: "Continuously track your location while a trip is active",
                                isOn: $trackMyLocationDuringTrip
                            )
                            
                            Divider()
                            
                            SettingToggleRow(
                                title: "Show my active trip on the large map",
                                description: "Display your active trip on the full-screen map",
                                isOn: $showMyActiveTripOnLargeMap
                            )
                            .disabled(!trackMyLocationDuringTrip)
                            .opacity(trackMyLocationDuringTrip ? 1.0 : 0.5)
                            
                            Divider()
                            
                            SettingToggleRow(
                                title: "Show my active trip on the small map",
                                description: "Display your active trip on the small map",
                                isOn: $showMyActiveTripOnSmallMap
                            )
                            .disabled(!trackMyLocationDuringTrip)
                            .opacity(trackMyLocationDuringTrip ? 1.0 : 0.5)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .background(Color.Theme.cardBackground)
                        .cornerRadius(20)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                        .listRowBackground(Color.clear)
                    } header: {
                        Text("Trip Settings")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(Color.Theme.primaryBlue)
                    }
                    .textCase(nil)
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("New Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(Color.Theme.primaryBlue)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        var enabledCountries: [PlateRegion.Country] = []
                        if includeUS { enabledCountries.append(.unitedStates) }
                        if includeCanada { enabledCountries.append(.canada) }
                        if includeMexico { enabledCountries.append(.mexico) }
                        
                        // Ensure at least one country is selected
                        if enabledCountries.isEmpty {
                            enabledCountries = [.unitedStates, .canada, .mexico]
                        }
                        
                        let tripData = ContentView.TripCreationData(
                            name: tripName.isEmpty ? nil : tripName,
                            enabledCountries: enabledCountries,
                            startTripRightAway: startTripRightAway,
                            skipVoiceConfirmation: skipVoiceConfirmation,
                            holdToTalk: holdToTalk,
                            saveLocationWhenMarkingPlates: saveLocationWhenMarkingPlates,
                            showMyLocationOnLargeMap: showMyLocationOnLargeMap,
                            trackMyLocationDuringTrip: trackMyLocationDuringTrip,
                            showMyActiveTripOnLargeMap: showMyActiveTripOnLargeMap,
                            showMyActiveTripOnSmallMap: showMyActiveTripOnSmallMap
                        )
                        onCreate(tripData)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                }
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

private struct TripRow: View {
    let trip: Trip

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(trip.name)
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)

                Spacer()

              Label("\(trip.foundRegionIDs.count)/\(PlateRegion.all.count)", systemImage: "scope")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.medium)
                    .foregroundStyle(Color.Theme.accentYellow)
            }

            Divider()
                .background(Color.Theme.softBrown.opacity(0.2))

            HStack {
              Label(trip.startedAt != nil ? "Started" :"Created", systemImage: "calendar")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)

                Spacer()

              Text(dateFormatter.string(from: trip.startedAt != nil ? trip.startedAt! : trip.createdAt))
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.Theme.cardBackground)
                .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
        )
    }
}

private struct TripMissingView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.Theme.accentYellow)
            Text("Trip Unavailable")
                .font(.system(.title2, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(Color.Theme.primaryBlue)
            Text("We could not find the trip you were looking for.")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.Theme.background)
    }
}

// App Preferences enums are now in Core/AppPreferences.swift

// Default Settings View for new trips
private struct DefaultSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var systemColorScheme
    @AppStorage("defaultSkipVoiceConfirmation") private var defaultSkipVoiceConfirmation = false
    @AppStorage("defaultHoldToTalk") private var defaultHoldToTalk = true
    @AppStorage("defaultStartTripRightAway") private var defaultStartTripRightAway = false
    @AppStorage("defaultIncludeUS") private var defaultIncludeUS = true
    @AppStorage("defaultIncludeCanada") private var defaultIncludeCanada = true
    @AppStorage("defaultIncludeMexico") private var defaultIncludeMexico = true
    @AppStorage("defaultSaveLocationWhenMarkingPlates") private var defaultSaveLocationWhenMarkingPlates = true
    @AppStorage("defaultShowMyLocationOnLargeMap") private var defaultShowMyLocationOnLargeMap = true
    @AppStorage("defaultTrackMyLocationDuringTrip") private var defaultTrackMyLocationDuringTrip = true
    @AppStorage("defaultShowMyActiveTripOnLargeMap") private var defaultShowMyActiveTripOnLargeMap = true
    @AppStorage("defaultShowMyActiveTripOnSmallMap") private var defaultShowMyActiveTripOnSmallMap = true
    
    // App Preferences
    @AppStorage("appDarkMode") private var appDarkModeRaw: String = AppDarkMode.system.rawValue
    
    // Use @State to explicitly track color scheme and ensure view updates
    @State private var currentColorScheme: ColorScheme?
    
    // Computed property to determine color scheme from preference
    private func updateColorScheme() {
      print("Current: \(appDarkModeRaw)--System: \(systemColorScheme)")
        let darkMode = AppDarkMode(rawValue: appDarkModeRaw) ?? .system
        switch darkMode {
        case .light:
            currentColorScheme = .light
        case .dark:
            currentColorScheme = .dark
        case .system:
            // When system, use the actual system color scheme
            currentColorScheme = systemColorScheme
        }
    }
    @AppStorage("appDistanceUnit") private var appDistanceUnitRaw: String = AppDistanceUnit.miles.rawValue
    @AppStorage("appMapStyle") private var appMapStyleRaw: String = AppMapStyle.standard.rawValue
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.english.rawValue
    @AppStorage("appPlaySoundEffects") private var appPlaySoundEffects = true
    @AppStorage("appUseVibrations") private var appUseVibrations = true
    
    @EnvironmentObject var authService: FirebaseAuthService
    @Environment(\.modelContext) private var modelContext
    @State private var showUserProfile = false
    
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
    
    enum SettingsSection: String, CaseIterable {
        case user = "User"
        case privacyPermissions = "Privacy & Permissions"
        case appPreferences = "App Preferences"
        case newTripDefaults = "New Trip Defaults"
        case voice = "Voice Defaults"
        case helpAbout = "Help & About"
        
        var id: String { rawValue }
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
                            case .user:
                              userSettings
                            case .privacyPermissions:
                              privacyPermissionsSettings
                            case .appPreferences:
                              appPreferencesSettings
                            case .newTripDefaults:
                              newTripDefaultsSettings
                            case .voice:
                              voiceSettings
                            case .helpAbout:
                              helpAboutSettings
                            }
                          }
                          .background(Color.Theme.cardBackground)
                          .cornerRadius(20)
                        } header: {
                            Text(section.rawValue)
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
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
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
            .navigationDestination(isPresented: $showUserProfile) {
                if let user = authService.currentUser {
                    UserProfileView(user: user, authService: authService)
                }
            }
            .navigationDestination(isPresented: $showAbout) {
              AboutView()
            }
            .navigationDestination(isPresented: $showAcknowledgements) {
              AcknowledgementsView()
            }
            .navigationDestination(isPresented: $showFAQ) {
              FAQView()
            }
            .navigationDestination(isPresented: $showTerms) {
              TermsView()
            }
            .navigationDestination(isPresented: $showPrivacy) {
              PrivacyView()
            }
        }
        .background(Color.Theme.background)
    }
    
    private var userSettings: some View {
        Group {
            if let _ = authService.currentUser {
                SettingNavigationRow(
                    title: "Profile",
                    description: "Edit username and manage account"
                ) {
                    showUserProfile = true
                }
            }
        }
    }
    
    // Privacy & Permissions
    @AppStorage("saveLocationWhenMarkingPlates") private var saveLocationWhenMarkingPlates = true
    @AppStorage("showMyLocationOnLargeMap") private var showMyLocationOnLargeMap = true
    @AppStorage("trackMyLocationDuringTrips") private var trackMyLocationDuringTrips = true
    @AppStorage("notifyPlateFoundByOpponent") private var notifyPlateFoundByOpponent = true
    @AppStorage("notifyPlateFoundByCoPilots") private var notifyPlateFoundByCoPilots = true
    @AppStorage("notifyPromotionsAndNews") private var notifyPromotionsAndNews = false
    
    @StateObject private var locationManager = LocationManager()
    @State private var microphonePermission: AVAudioSession.RecordPermission = .undetermined
    @State private var speechRecognitionPermission: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @State private var cameraPermission: AVAuthorizationStatus = .notDetermined
    @State private var notificationPermission: UNAuthorizationStatus = .notDetermined
    
    private var privacyPermissionsSettings: some View {
        Group {
            // Location Permission
            PermissionRow(
                title: "Location",
                icon: "location.fill",
                status: locationPermissionStatus,
                statusColor: locationPermissionColor,
                onTap: openLocationSettings
            )
            
            SettingToggleRow(
                title: "Save location when marking plates",
                description: "Store location data when you mark a plate as found",
                isOn: $saveLocationWhenMarkingPlates
            )
            
            SettingToggleRow(
                title: "Show my location on large map",
                description: "Display your current location on the full-screen map",
                isOn: $showMyLocationOnLargeMap
            )
            
            SettingToggleRow(
                title: "Track my location during trips",
                description: "Continuously track your location while a trip is active (Can be disabled at any time)",
                isOn: $trackMyLocationDuringTrips
            )
          
          Divider()
            
            // Microphone Permission
            PermissionRow(
                title: "Microphone",
                icon: "mic.fill",
                status: microphonePermissionStatus,
                statusColor: microphonePermissionColor,
                onTap: openMicrophoneSettings
            )
          
          Divider()
            
            // Speech Recognizer Permission
            PermissionRow(
                title: "Speech Recognizer",
                icon: "waveform",
                status: speechRecognitionPermissionStatus,
                statusColor: speechRecognitionPermissionColor,
                onTap: openSpeechRecognitionSettings
            )
          
          Divider()
            
            // Camera Permission (hidden for now)
            if false {
                PermissionRow(
                    title: "Camera",
                    icon: "camera.fill",
                    status: cameraPermissionStatus,
                    statusColor: cameraPermissionColor,
                    onTap: openCameraSettings
                )
              
              Divider()
            }
            
            // Notifications Permission
            PermissionRow(
                title: "Notifications",
                icon: "bell.fill",
                status: notificationPermissionStatus,
                statusColor: notificationPermissionColor,
                onTap: openNotificationSettings
            )
            
            SettingToggleRow(
                title: "Plate found by opponent",
                description: "Get notified when an opponent finds a plate",
                isOn: $notifyPlateFoundByOpponent
            )
            
            SettingToggleRow(
                title: "Plate found by co-pilots",
                description: "Get notified when a co-pilot finds a plate",
                isOn: $notifyPlateFoundByCoPilots
            )
            
            SettingToggleRow(
                title: "Promotion & News",
                description: "Receive promotional offers and app news",
                isOn: $notifyPromotionsAndNews
            )
        }
        .onAppear {
            checkPermissions()
        }
        .onChange(of: locationManager.authorizationStatus) { oldValue, newValue in
            checkPermissions()
        }
    }
    
    // Permission status helpers
    private var locationPermissionStatus: String {
        switch locationManager.authorizationStatus {
        case .authorizedAlways:
            return "Allowed"
        case .authorizedWhenInUse:
            return "While App is Open"
        case .denied, .restricted:
            return "Disabled"
        case .notDetermined:
            return "Not Set"
        @unknown default:
            return "Unknown"
        }
    }
    
    private var locationPermissionColor: Color {
        switch locationManager.authorizationStatus {
        case .authorizedAlways:
            return .green
        case .authorizedWhenInUse:
            return Color.Theme.permissionYellow
        case .denied, .restricted:
            return .red
        case .notDetermined:
            return Color.Theme.permissionOrangeDark
        @unknown default:
            return Color.Theme.permissionOrangeDark
        }
    }
    
    private var microphonePermissionStatus: String {
        switch microphonePermission {
        case .granted:
            return "Allowed"
        case .denied:
            return "Disabled"
        case .undetermined:
            return "Not Set"
        @unknown default:
            return "Unknown"
        }
    }
    
    private var microphonePermissionColor: Color {
        switch microphonePermission {
        case .granted:
            return .green
        case .denied:
            return .red
        case .undetermined:
            return Color.Theme.permissionOrange
        @unknown default:
            return Color.Theme.permissionOrange
        }
    }
    
    private var speechRecognitionPermissionStatus: String {
        switch speechRecognitionPermission {
        case .authorized:
            return "Allowed"
        case .denied, .restricted:
            return "Disabled"
        case .notDetermined:
            return "Not Set"
        @unknown default:
            return "Unknown"
        }
    }
    
    private var speechRecognitionPermissionColor: Color {
        switch speechRecognitionPermission {
        case .authorized:
            return .green
        case .denied, .restricted:
            return .red
        case .notDetermined:
            return Color.Theme.permissionOrange
        @unknown default:
            return Color.Theme.permissionOrange
        }
    }
    
    private var cameraPermissionStatus: String {
        switch cameraPermission {
        case .authorized:
            return "Allowed"
        case .denied, .restricted:
            return "Disabled"
        case .notDetermined:
            return "Not Set"
        @unknown default:
            return "Unknown"
        }
    }
    
    private var cameraPermissionColor: Color {
        switch cameraPermission {
        case .authorized:
            return .green
        case .denied, .restricted:
            return .red
        case .notDetermined:
            return Color.Theme.permissionOrange
        @unknown default:
            return Color.Theme.permissionOrange
        }
    }
    
    private var notificationPermissionStatus: String {
        switch notificationPermission {
        case .authorized, .provisional, .ephemeral:
            return "Allowed"
        case .denied:
            return "Disabled"
        case .notDetermined:
            return "Not Set"
        @unknown default:
            return "Unknown"
        }
    }
    
    private var notificationPermissionColor: Color {
        switch notificationPermission {
        case .authorized, .provisional, .ephemeral:
            return .green
        case .denied:
            return .red
        case .notDetermined:
            return Color.Theme.permissionOrange
        @unknown default:
            return Color.Theme.permissionOrange
        }
    }
    
    private func checkPermissions() {
        // Check microphone permission
        microphonePermission = AVAudioSession.sharedInstance().recordPermission
        
        // Check speech recognition permission
        speechRecognitionPermission = SFSpeechRecognizer.authorizationStatus()
        
        // Check camera permission
        cameraPermission = AVCaptureDevice.authorizationStatus(for: .video)
        
        // Check notification permission
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            await MainActor.run {
                notificationPermission = settings.authorizationStatus
            }
        }
    }
    
    private func openLocationSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
    
    private func openMicrophoneSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
    
    private func openSpeechRecognitionSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
    
    private func openCameraSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
    
    private func openNotificationSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
    
    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
    
    private var appPreferencesSettings: some View {
        Group {
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
    }
    
    private var newTripDefaultsSettings: some View {
        Group {
            // Countries
            VStack(alignment: .leading, spacing: 12) {
                Text("Default Countries")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .padding(.bottom, 4)
                
                CountryCheckboxRow(title: "United States", isOn: $defaultIncludeUS)
                CountryCheckboxRow(title: "Canada", isOn: $defaultIncludeCanada)
                CountryCheckboxRow(title: "Mexico", isOn: $defaultIncludeMexico)
            }
            
            Divider()
            
            SettingToggleRow(
                title: "Start Trip right away",
                description: "Automatically start new trips when created",
                isOn: $defaultStartTripRightAway
            )
            
            Divider()
            
            SettingToggleRow(
                title: "Save location when marking plates",
                description: "Store location data when marking plates (default for new trips)",
                isOn: $defaultSaveLocationWhenMarkingPlates
            )
            
            Divider()
            
            SettingToggleRow(
                title: "Show my location on large map",
                description: "Display current location on full-screen map (default for new trips)",
                isOn: $defaultShowMyLocationOnLargeMap
            )
            
            Divider()
            
            SettingToggleRow(
                title: "Track my location during trip",
                description: "Continuously track location while trip is active (default for new trips)",
                isOn: $defaultTrackMyLocationDuringTrip
            )
            
            Divider()
            
            SettingToggleRow(
                title: "Show my active trip on the large map",
                description: "Display active trip on full-screen map (default for new trips)",
                isOn: $defaultShowMyActiveTripOnLargeMap
            )
            .disabled(!defaultTrackMyLocationDuringTrip)
            .opacity(defaultTrackMyLocationDuringTrip ? 1.0 : 0.5)
            
            Divider()
            
            SettingToggleRow(
                title: "Show my active trip on the small map",
                description: "Display active trip on small map (default for new trips)",
                isOn: $defaultShowMyActiveTripOnSmallMap
            )
            .disabled(!defaultTrackMyLocationDuringTrip)
            .opacity(defaultTrackMyLocationDuringTrip ? 1.0 : 0.5)
        }
    }
    
    private var voiceSettings: some View {
        Group {
            SettingToggleRow(
                title: "Skip Voice Confirmation",
                description: "Automatically add license plates heard by speech recognition without requiring user confirmation. This is the default for NEW trips created, this can be changed per trip as well.",
                isOn: $defaultSkipVoiceConfirmation
            )
          if false {
            Divider()
            
            SettingToggleRow(
              title: "Hold to Talk",
              description: "Press and hold the microphone button to record. If disabled the system will listen until you hit stop. This is the default for NEW trips created, this can be changed per trip as well.",
              isOn: $defaultHoldToTalk
            )
          }
        }
    }
    
    @State private var showAbout = false
    @State private var showAcknowledgements = false
    @State private var showFAQ = false
    @State private var showTerms = false
    @State private var showPrivacy = false
    
    private var helpAboutSettings: some View {
        Group {
            SettingNavigationRow(
                title: "About",
                description: "Learn about RoadTrip Royale and HammersTechLLC"
            ) {
                showAbout = true
            }
          
          Divider()
            
            SettingNavigationRow(
                title: "Acknowledgements",
                description: "Open source libraries and SDKs we use"
            ) {
                showAcknowledgements = true
            }
          
          Divider()
            
            SettingNavigationRow(
                title: "FAQ",
                description: "Frequently asked questions"
            ) {
                showFAQ = true
            }
          
          Divider()
            
            Button {
                sendEmail(to: "hammerstechllc@gmail.com", subject: "RoadTrip Royale Bug Report")
            } label: {
                HStack(spacing: 16) {
                    Image(systemName: "ladybug")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.Theme.primaryBlue)
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Report a Bug")
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.Theme.primaryBlue)
                        
                        Text("Help us improve by reporting issues")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                    }
                    
                    Spacer()
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.Theme.cardBackground)
                )
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
            
          Divider()
          
            Button {
                sendEmail(to: "hammerstechllc@gmail.com", subject: "RoadTrip Royale Feature Suggestion")
            } label: {
                HStack(spacing: 16) {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.Theme.primaryBlue)
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Suggest a Feature")
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.Theme.primaryBlue)
                        
                        Text("Share your ideas for new features")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                    }
                    
                    Spacer()
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.Theme.cardBackground)
                )
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
            
          Divider()
          
            Button {
                sendEmail(to: "hammerstechllc@gmail.com", subject: "RoadTrip Royale Support Issue")
            } label: {
                HStack(spacing: 16) {
                    Image(systemName: "envelope")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.Theme.primaryBlue)
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Contact Support")
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.Theme.primaryBlue)
                        
                        Text("Get help with the app")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                    }
                    
                    Spacer()
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.Theme.cardBackground)
                )
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
            
          Divider()
          
            // App Version and Legal
            VStack(spacing: 12) {
                Text("App Version \(appVersion)")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                
                HStack(spacing: 20) {
                    // Terms button - isolated tap area
                    Text("Terms")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.Theme.primaryBlue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            showTerms = true
                        }
                    
                    Text("·")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                        .allowsHitTesting(false)
                    
                    // Privacy button - isolated tap area
                    Text("Privacy")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.Theme.primaryBlue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            showPrivacy = true
                        }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
            .listRowSeparator(.hidden)
            .contentShape(Rectangle())
            .allowsHitTesting(true)
        }
    }
    
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    private func sendEmail(to email: String, subject: String) {
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
        if let url = URL(string: "mailto:\(email)?subject=\(encodedSubject)") {
            UIApplication.shared.open(url)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Trip.self, inMemory: true)
}

// MARK: - Help & About Views

private struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("RoadTrip Royale")
                        .font(.system(.largeTitle, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                    
                    Text("About the App")
                        .font(.system(.title2, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                    
                    Text("RoadTrip Royale is a fun and engaging license plate tracking game that lets you collect license plates from across the United States, Canada, and Mexico during your road trips. Spot plates, track your progress, and see your collection grow on an interactive map!")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                    
                    Text("About HammersTechLLC")
                        .font(.system(.title2, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                        .padding(.top)
                    
                    Text("RoadTrip Royale is developed by HammersTechLLC, a software development company dedicated to creating innovative and user-friendly mobile applications. We're passionate about building apps that make everyday activities more enjoyable and engaging.")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                    
                    Text("Contact")
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                        .padding(.top)
                    
                    Text("Email: hammerstechllc@gmail.com")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                }
                .padding()
            }
            .background(Color.Theme.background)
            .navigationTitle("About")
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
        }
    }
}

private struct AcknowledgementsView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Acknowledgements")
                        .font(.system(.largeTitle, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                    
                    Text("RoadTrip Royale uses the following open source libraries and SDKs:")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                    
                    VStack(alignment: .leading, spacing: 16) {
                        AcknowledgementItem(
                            name: "Firebase",
                            description: "Backend services including Authentication, Firestore, and Storage",
                            url: "https://firebase.google.com"
                        )
                        
                        AcknowledgementItem(
                            name: "Google Sign-In",
                            description: "OAuth authentication for Google accounts",
                            url: "https://developers.google.com/identity/sign-in/ios"
                        )
                        
                        AcknowledgementItem(
                            name: "Apple Authentication Services",
                            description: "Sign in with Apple integration",
                            url: "https://developer.apple.com/sign-in-with-apple/"
                        )
                        
                        AcknowledgementItem(
                            name: "SwiftUI",
                            description: "Apple's declarative UI framework",
                            url: "https://developer.apple.com/xcode/swiftui/"
                        )
                        
                        AcknowledgementItem(
                            name: "SwiftData",
                            description: "Apple's data persistence framework",
                            url: "https://developer.apple.com/documentation/swiftdata"
                        )
                        
                        AcknowledgementItem(
                            name: "MapKit",
                            description: "Apple's mapping and location services",
                            url: "https://developer.apple.com/mapkit/"
                        )
                        
                        AcknowledgementItem(
                            name: "Speech Framework",
                            description: "Apple's speech recognition framework",
                            url: "https://developer.apple.com/documentation/speech"
                        )
                    }
                }
                .padding()
            }
            .background(Color.Theme.background)
            .navigationTitle("Acknowledgements")
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
        }
    }
}

private struct AcknowledgementItem: View {
    let name: String
    let description: String
    let url: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(name)
                .font(.system(.headline, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(Color.Theme.primaryBlue)
            
            Text(description)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.Theme.cardBackground)
        )
    }
}

private struct FAQView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Frequently Asked Questions")
                        .font(.system(.largeTitle, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                    
                    FAQItem(
                        question: "How do I play RoadTrip Royale?",
                        answer: "RoadTrip Royale is a license plate tracking game! During your road trips, keep an eye out for license plates from different states, provinces, or regions. When you spot one, use the app to mark it as found. You can use the List tab to manually select plates, or the Voice tab to speak the state/province name. Track your progress and see your collection grow on the interactive map!"
                    )
                    
                    FAQItem(
                        question: "How do I create a trip?",
                        answer: "On the main screen, tap the 'Create Trip' button. You can give your trip a custom name, or leave it blank to use the date and time automatically. Once created, tap on the trip to start tracking license plates!"
                    )
                    
                    FAQItem(
                        question: "How does the Voice feature work?",
                        answer: "Tap the Voice tab, then press the microphone button. Speak the name of the state or province you see (e.g., 'California' or 'Ontario'). The app will listen and try to match what you said to a valid license plate region. If a match is found, you'll be asked to confirm before adding it to your collection."
                    )
                    
                    FAQItem(
                        question: "Can I track plates from multiple countries?",
                        answer: "Yes! RoadTrip Royale supports license plates from the United States, Canada, and Mexico. The map will automatically switch to show the correct country as you scroll through the list of regions."
                    )
                    
                    FAQItem(
                        question: "How do I see my progress?",
                        answer: "On the trip screen, you'll see summary chips showing how many plates you've found and how many remain. The map at the top shows all found regions highlighted in yellow. You can tap the map to view it full-screen for a better look!"
                    )
                    
                    FAQItem(
                        question: "Can I share my trips with others?",
                        answer: "Currently, trips are stored locally on your device. Future updates may include sharing and collaboration features. Stay tuned!"
                    )
                    
                    FAQItem(
                        question: "Do I need an internet connection?",
                        answer: "RoadTrip Royale works offline! You can create trips and track license plates without an internet connection. If you sign in with an account, your data will sync to the cloud when you're online."
                    )
                }
                .padding()
            }
            .background(Color.Theme.background)
            .navigationTitle("FAQ")
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
        }
    }
}

private struct FAQItem: View {
    let question: String
    let answer: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(question)
                .font(.system(.headline, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(Color.Theme.primaryBlue)
            
            Text(answer)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.Theme.cardBackground)
        )
    }
}

private struct TermsView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Terms of Service")
                        .font(.system(.largeTitle, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                    
                    Text("Last Updated: \(Date().formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                    
                    Text("1. Acceptance of Terms")
                        .font(.system(.headline, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                        .padding(.top)
                    
                    Text("By downloading, installing, or using RoadTrip Royale, you agree to be bound by these Terms of Service. If you do not agree to these terms, please do not use the app.")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                    
                    Text("2. Use of the App")
                        .font(.system(.headline, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                        .padding(.top)
                    
                    Text("RoadTrip Royale is provided for personal, non-commercial use. You may not use the app for any illegal or unauthorized purpose. You are responsible for maintaining the security of your account.")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                    
                    Text("3. User Content")
                        .font(.system(.headline, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                        .padding(.top)
                    
                    Text("You retain ownership of any data you create using RoadTrip Royale. By using the app, you grant HammersTechLLC the right to store and process your data to provide the service.")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                    
                    Text("4. Limitation of Liability")
                        .font(.system(.headline, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                        .padding(.top)
                    
                    Text("HammersTechLLC shall not be liable for any indirect, incidental, special, or consequential damages arising from your use of RoadTrip Royale.")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                    
                    Text("5. Changes to Terms")
                        .font(.system(.headline, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                        .padding(.top)
                    
                    Text("We reserve the right to modify these terms at any time. Continued use of the app after changes constitutes acceptance of the new terms.")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                }
                .padding()
            }
            .background(Color.Theme.background)
            .navigationTitle("Terms of Service")
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
        }
    }
}

private struct PrivacyView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Privacy Policy")
                        .font(.system(.largeTitle, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                    
                    Text("Last Updated: \(Date().formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                    
                    Text("1. Information We Collect")
                        .font(.system(.headline, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                        .padding(.top)
                    
                    Text("RoadTrip Royale collects the following information:\n\n• Account information (username, email, phone) if you create an account\n• Trip data and license plate tracking information\n• Location data (optional, with your permission)\n• Device information for app functionality")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                    
                    Text("2. How We Use Your Information")
                        .font(.system(.headline, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                        .padding(.top)
                    
                    Text("We use your information to:\n\n• Provide and improve the app's functionality\n• Sync your data across devices (if you sign in)\n• Respond to support requests\n• Ensure app security and prevent fraud")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                    
                    Text("3. Data Storage")
                        .font(.system(.headline, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                        .padding(.top)
                    
                    Text("Your data is stored locally on your device. If you sign in with an account, your data is also stored securely in Firebase (Google Cloud Platform) to enable syncing across devices.")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                    
                    Text("4. Third-Party Services")
                        .font(.system(.headline, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                        .padding(.top)
                    
                    Text("RoadTrip Royale uses Firebase (Google) for authentication and data storage. Your use of these services is subject to their respective privacy policies.")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                    
                    Text("5. Your Rights")
                        .font(.system(.headline, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                        .padding(.top)
                    
                    Text("You have the right to:\n\n• Access your personal data\n• Delete your account and data\n• Opt out of data collection (though this may limit app functionality)\n• Contact us with privacy concerns")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                    
                    Text("6. Contact Us")
                        .font(.system(.headline, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                        .padding(.top)
                    
                    Text("For privacy-related questions, contact us at:\n\nEmail: hammerstechllc@gmail.com")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                }
                .padding()
            }
            .background(Color.Theme.background)
            .navigationTitle("Privacy Policy")
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
        }
    }
}

// MARK: - Permission Row Component

private struct PermissionRow: View {
    let title: String
    let icon: String
    let status: String
    let statusColor: Color
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                }
                
                Spacer()
                
                Text(status)
                    .font(.system(.caption, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(statusColor)
              
            if statusColor != .green {
              Image(systemName: "arrow.up.right.square")
                  .font(.system(size: 12))
                  .foregroundStyle(Color.Theme.primaryBlue)
            }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.Theme.cardBackground)
            )
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
    }
}
