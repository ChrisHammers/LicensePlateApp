//
//  ContentView.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import SwiftUI
import SwiftData
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
    @AppStorage("boundariesLoaded") private var boundariesLoaded = false
    
    // Custom detent for the new trip sheet - device-aware sizing
    // On iPad, use a larger fraction since 25% is too small to show the text field
    private var smallDetent: PresentationDetent {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return PresentationDetent.fraction(0.4) // 40% on iPad
        } else {
            return PresentationDetent.fraction(0.25) // 25% on iPhone
        }
    }
    @State private var sheetDetent: PresentationDetent = {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return PresentationDetent.fraction(0.4)
        } else {
            return PresentationDetent.fraction(0.25)
        }
    }()
    
    // App Preferences
    @AppStorage("appDarkMode") private var appDarkModeRaw: String = AppDarkMode.system.rawValue
    @AppStorage("appPlaySoundEffects") private var appPlaySoundEffects = true
    @AppStorage("appUseVibrations") private var appUseVibrations = true
    
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
        ZStack {
            if boundariesLoaded {
              NavigationStack(path: $path) {
                AppBackgroundView {
                  List {
                    Section {
                        header
                            .listRowInsets(.init(top: 24, leading: 20, bottom: 24, trailing: 20))
                            .listRowBackground(Color.clear)
                    }
                    .textCase(nil)

                    // Family Section
                    Section {
                        NavigationLink {
                            FamilyHubView()
                        } label: {
                            HStack {
                                Image(systemName: "person.3.fill")
                                    .foregroundStyle(Color.Theme.primaryBlue)
                                    .frame(width: 24)
                                Text("Family".localized)
                                    .font(.headline)
                            }
                        }
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
                        Section("Trips".localized) {
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
                    .accessibilityLabel("Settings".localized)
                    .accessibilityHint("Opens app settings".localized)
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
                .transition(.opacity)
            } else {
                SplashScreenView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: boundariesLoaded)
        .preferredColorScheme(currentColorScheme)
        .onAppear {
            FeedbackService.shared.updatePreferences(hapticEnabled: appUseVibrations, soundEnabled: appPlaySoundEffects)
            
            // Mark boundaries as loaded after splash screen has rendered
            // This ensures the splash screen is visible before transitioning
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                // Boundaries are already loaded in AppDelegate, so we can safely mark as complete
                boundariesLoaded = true
            }
        }
        .onChange(of: appUseVibrations) { _, newValue in
            FeedbackService.shared.updatePreferences(hapticEnabled: newValue, soundEnabled: appPlaySoundEffects)
        }
        .onChange(of: appPlaySoundEffects) { _, newValue in
            FeedbackService.shared.updatePreferences(hapticEnabled: appUseVibrations, soundEnabled: newValue)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RoadTrip Royale".localized)
                .font(.system(.largeTitle, design: .rounded))
                .fontWeight(.bold)
                .foregroundStyle(Color.Theme.primaryBlue)
                .shadow(color: Color.Theme.primaryBlue.opacity(0.5), radius: 5)
            
            Text("Spot license plates, conquer the map, and rule the open road!".localized)
                .font(.system(.title2, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(Color.Theme.primaryBlue.opacity(0.8))

            Text("Track every plate you see across the United States, Canada, and Mexico.".localized)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "car.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.Theme.accentYellow)

            Text("No trips yet".localized)
                .font(.system(.title2, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(Color.Theme.primaryBlue)

            Text("Start your first adventure and begin collecting plates from across North America.".localized)
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
            .accessibilityLabel("Trip: %@".localized(trip.name))
            .accessibilityHint("Double tap to open trip".localized)
        }
        .onDelete(perform: deleteTrips)
    }

    private var addTripButton: some View {
        Button {
            FeedbackService.shared.buttonTap()
            isShowingCreateSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24, weight: .bold))
                    .accessibilityHidden(true)
                Text("Create Trip".localized)
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
        .accessibilityLabel("Create Trip".localized)
        .accessibilityHint("Opens a sheet to create a new trip".localized)
        .accessibilityAddTraits(.isButton)
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
            FeedbackService.shared.actionSuccess()
        } catch {
            FeedbackService.shared.actionError()
            // In a production app, handle the error appropriately.
            assertionFailure("Failed to save new trip: \(error)")
        }

        path.append(newTrip.id)
    }

    private func deleteTrips(at offsets: IndexSet) {
        FeedbackService.shared.buttonTap()
            for index in offsets {
            modelContext.delete(trips[index])
        }
        do {
            try modelContext.save()
            FeedbackService.shared.actionSuccess()
        } catch {
            FeedbackService.shared.actionError()
            assertionFailure("Failed to delete trip: \(error)")
        }
    }
}

private struct NewTripSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tripName: String = ""
    
    // App Preferences for feedback
    @AppStorage("appPlaySoundEffects") private var appPlaySoundEffects = true
    @AppStorage("appUseVibrations") private var appUseVibrations = true
    
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
                            Text("Trip Name".localized)
                                .font(.system(.headline, design: .rounded))
                                .foregroundStyle(Color.Theme.primaryBlue)
                            
                            TextField("Automatically use date & time".localized, text: $tripName)
                                .textInputAutocapitalization(.words)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.Theme.background)
                                )
                                .accessibilityLabel("Trip Name".localized)
                                .accessibilityHint("Enter a name for your trip, or leave blank to use date and time".localized)
                                .accessibilityValue(tripName.isEmpty ? "Will use date and time".localized : tripName)
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
                    
                    Section {
                        VStack(spacing: 12) {
                            // Start Trip
                            SettingToggleRow(
                                title: "Start Trip right away".localized,
                                description: "Automatically start the trip when created".localized,
                                isOn: $startTripRightAway
                            )
                            
                            Divider()
                            
                            // Countries
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Countries to Include".localized)
                                    .font(.system(.headline, design: .rounded))
                                    .foregroundStyle(Color.Theme.primaryBlue)
                                
                                CountryCheckboxRow(title: "United States".localized, isOn: $includeUS)
                                CountryCheckboxRow(title: "Canada".localized, isOn: $includeCanada)
                                CountryCheckboxRow(title: "Mexico".localized, isOn: $includeMexico)
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
                    
                    Section {
                        VStack(spacing: 12) {
                            // Voice Settings
                            SettingToggleRow(
                                title: "Skip Voice Confirmation".localized,
                                description: "Automatically add license plates without confirmation when using Voice".localized,
                                isOn: $skipVoiceConfirmation
                            )
                            
                            Divider()
                            
                            // Location Settings
                            SettingToggleRow(
                                title: "Save location when marking plates".localized,
                                description: "Store location data when you mark a plate as found".localized,
                                isOn: $saveLocationWhenMarkingPlates
                            )
                            
                            Divider()
                            
                            SettingToggleRow(
                                title: "Show my location on large map".localized,
                                description: "Display your current location on the full-screen map".localized,
                                isOn: $showMyLocationOnLargeMap
                            )
                            
                            Divider()
                            
                            SettingToggleRow(
                                title: "Track my location during trip".localized,
                                description: "Continuously track your location while a trip is active".localized,
                                isOn: $trackMyLocationDuringTrip
                            )
                            
                            Divider()
                            
                            SettingToggleRow(
                                title: "Show my active trip on the large map".localized,
                                description: "Display your active trip on the full-screen map".localized,
                                isOn: $showMyActiveTripOnLargeMap
                            )
                            .disabled(!trackMyLocationDuringTrip)
                            .opacity(trackMyLocationDuringTrip ? 1.0 : 0.5)
                            
                            Divider()
                            
                            SettingToggleRow(
                                title: "Show my active trip on the small map".localized,
                                description: "Display your active trip on the small map".localized,
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
                        Text("Trip Settings".localized)
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(Color.Theme.primaryBlue)
                    }
                    .textCase(nil)
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("New Trip".localized)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                FeedbackService.shared.updatePreferences(hapticEnabled: appUseVibrations, soundEnabled: appPlaySoundEffects)
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
                        FeedbackService.shared.buttonTap()
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

              Label("\(trip.foundRegionIDs.count)/\(PlateRegion.all.count)", systemImage: "licenseplate")//scope used before, works with Royale theme though.
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.medium)
                    .foregroundStyle(Color.Theme.accentYellow)
                    .accessibilityLabel("Progress: \(trip.foundRegionIDs.count) of \(PlateRegion.all.count) regions found")
            }

            Divider()
                .background(Color.Theme.softBrown.opacity(0.2))
                .accessibilityHidden(true)

            HStack {
              Label(trip.startedAt != nil ? "Started".localized :"Created".localized, systemImage: "calendar")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                    .accessibilityLabel(trip.startedAt != nil ? "Started".localized : "Created".localized)

                Spacer()

              Text(dateFormatter.string(from: trip.startedAt != nil ? trip.startedAt! : trip.createdAt))
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                    .accessibilityLabel("Date: \(dateFormatter.string(from: trip.startedAt != nil ? trip.startedAt! : trip.createdAt))")
            }
            
            // Show "Ended on" date if trip has ended
            if trip.isTripEnded, let endedDate = trip.tripEndedAt {
                HStack {
                  Label {
                      Text("Ended".localized)
                              } icon: {
                                      Image(systemName: "star.fill")
                                          .font(.body) // Match font size for consistent sizing
                                          .opacity(0)
                              }
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                        .accessibilityLabel("Ended".localized)

                    Spacer()

                    Text(dateFormatter.string(from: endedDate))
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                        .accessibilityLabel("Date: \(dateFormatter.string(from: endedDate))")
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.Theme.cardBackground)
                .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
        )
        .accessibilityElement(children: .combine)
    }
}

private struct TripMissingView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.Theme.accentYellow)
                .accessibilityHidden(true)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Trip Unavailable. We could not find the trip you were looking for.")
    }
}

// App Preferences enums are now in Core/AppPreferences.swift

// Default Settings View for new trips
struct DefaultSettingsView: View {
    @StateObject private var coordinator = MainSettingsCoordinator()
    @State private var navigationPath = NavigationPath()
    
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
        NavigationStack(path: $navigationPath) {
            ZStack {
                Color.Theme.background
                    .ignoresSafeArea()
                
                List {
                    Section {
                        VStack(spacing: 12) {
                            // Profile (from User section, but no section header)
                            if let _ = authService.currentUser {
                                SettingNavigationRow(
                                    title: "Profile".localized,
                                    description: "Edit username and manage account".localized,
                                    icon: "person.circle"
                                ) {
                                    coordinator.navigateToProfile(path: $navigationPath)
                                }
                                
                                Divider()
                            }
                            
                            // Privacy & Permissions
                            SettingNavigationRow(
                                title: "Privacy & Permissions".localized,
                                description: "Manage location, microphone, notifications, and other permissions".localized,
                                icon: "hand.raised.fill"
                            ) {
                                coordinator.navigateToPrivacyPermissions(path: $navigationPath)
                            }
                            
                            Divider()
                            
                            // App Preferences
                            SettingNavigationRow(
                                title: "App Preferences".localized,
                                description: "Customize dark mode, map style, and other app settings",
                                icon: "slider.horizontal.3"
                            ) {
                                coordinator.navigateToAppPreferences(path: $navigationPath)
                            }
                            
                            Divider()
                            
                            // New Trip Defaults
                            SettingNavigationRow(
                                title: "New Trip Defaults".localized,
                                description: "Set default countries, tracking, and voice settings for new trips".localized,
                                icon: "plus.circle.fill"
                            ) {
                                coordinator.navigateToNewTripDefaults(path: $navigationPath)
                            }
                            
                            Divider()
                            
                            // Family
                            SettingNavigationRow(
                                title: "Family".localized,
                                description: "Manage family members and shared trips".localized,
                                icon: "person.3.fill"
                            ) {
                                coordinator.navigateToFamily(path: $navigationPath)
                            }
                            
                            Divider()
                            
                          if false {
                            // Voice Defaults
                            SettingNavigationRow(
                              title: "Voice Defaults",
                              description: "Configure default voice recognition settings for new trips",
                              icon: "mic.fill"
                            ) {
                              coordinator.navigateToVoiceDefaults(path: $navigationPath)
                            }
                            
                            Divider()
                            
                          }
                            
                            // Help & About
                            SettingNavigationRow(
                                title: "Help & About".localized,
                                description: "Get help, report bugs, suggest features, and learn about the app".localized,
                                icon: "questionmark.circle.fill"
                            ) {
                                coordinator.navigateToHelpAbout(path: $navigationPath)
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
            .navigationDestination(for: MainSettingsCoordinator.SettingsDestination.self) { destination in
                Group {
                    switch destination {
                    case .profile:
                        if let user = authService.currentUser {
                            UserProfileView(user: user, authService: authService)
                        } else {
                            // Fallback view if no user (shouldn't happen since button is hidden)
                            Text("No user available")
                                .foregroundStyle(Color.Theme.softBrown)
                        }
                    case .privacyPermissions:
                        PrivacyPermissionsView()
                    case .appPreferences:
                        AppPreferencesView()
                    case .newTripDefaults:
                        NewTripDefaultsView()
                    case .voiceDefaults:
                        VoiceDefaultsView()
                    case .helpAbout:
                        HelpAboutView()
                    case .family:
                        FamilyHubView()
                    }
                }
            }
        }
        .background(Color.Theme.background)
    }
    
    // Removed: All settings content moved to separate view files
    // - PrivacyPermissionsView
    // - AppPreferencesView
    // - NewTripDefaultsView
    // - VoiceDefaultsView
    // - HelpAboutView
}

#Preview {
    ContentView()
        .modelContainer(for: Trip.self, inMemory: true)
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
