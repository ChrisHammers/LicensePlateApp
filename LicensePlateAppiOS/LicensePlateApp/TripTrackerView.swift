//
//  TripTrackerView.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//


import SwiftUI
import SwiftData
import Speech
import AudioToolbox
import MapKit
import CoreLocation

/***
 
 TripTrackerView: Main view while game/trip is open. Top area the Trip name, how many licenses found out max number and eventually a map that changes as you scroll or if you limit your choices.
 
 Tab bar to choose between  a list of states/provinces/regions that have license plates and if they are selected or not, and a voice option.
 
 

 */
struct TripTrackerView: View {
    enum Tab: CaseIterable, Identifiable {
        case list
        case voice

        var id: Self { self }

        var title: String {
            switch self {
            case .list: return "List"
            case .voice: return "Voice"
            }
        }

        var systemImage: String {
            switch self {
            case .list: return "list.bullet"
            case .voice: return "person.wave.2.fill"
            }
        }
    }

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authService: FirebaseAuthService
    @Bindable var trip: Trip
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @StateObject private var locationManager = LocationManager()
    
    // App Preferences for feedback
    @AppStorage("appPlaySoundEffects") private var appPlaySoundEffects = true
    @AppStorage("appUseVibrations") private var appUseVibrations = true

    @State private var selectedTab: Tab = .list
    @State private var lastMatchedRegion: PlateRegion?
    @State private var showVoiceMatchConfirmation = false
    @State private var lastProcessedText: String = ""
    @State private var showSettings = false
    @State private var visibleCountry: PlateRegion.Country = .unitedStates
    @State private var showFullScreenMap = false
    @Namespace private var mapNamespace

    var body: some View {
        VStack(spacing: 0) {
            header

            switch selectedTab {
            case .list:
                regionList
            case .voice:
                voiceCaptureView
            }

            customTabBar
        }
        .background(Color.Theme.background.ignoresSafeArea())
        .ignoresSafeArea(.all, edges: .bottom)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(trip.name)
        .toolbar {
            if !showFullScreenMap {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                       // FeedbackService.shared.buttonTap()
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundStyle(Color.Theme.primaryBlue)
                    }
                }
            }
        }
        .toolbar(showFullScreenMap ? .hidden : .visible, for: .navigationBar)
        .sheet(isPresented: $showSettings) {
            SettingsView(trip: trip, modelContext: modelContext)
                .environmentObject(authService)
        }
        .onAppear {
            FeedbackService.shared.updatePreferences(hapticEnabled: appUseVibrations, soundEnabled: appPlaySoundEffects)
        }
        .onChange(of: appUseVibrations) { _, newValue in
            FeedbackService.shared.updatePreferences(hapticEnabled: newValue, soundEnabled: appPlaySoundEffects)
        }
        .onChange(of: appPlaySoundEffects) { _, newValue in
            FeedbackService.shared.updatePreferences(hapticEnabled: appUseVibrations, soundEnabled: newValue)
        }
        .overlay {
            if showFullScreenMap {
                FullScreenMapView(
                    country: visibleCountry,
                    foundRegionIDs: trip.foundRegionIDs,
                    locationManager: locationManager,
                    namespace: mapNamespace,
                    isPresented: $showFullScreenMap
                )
                .transition(.opacity)
                .zIndex(1000)
            }
        }
        .onAppear {
            // Request location permission when view appears
            if locationManager.authorizationStatus == .notDetermined {
                locationManager.requestAuthorization()
            }
            // Switch to list tab if trip is not active and currently on voice tab
            if !isTripActive && selectedTab == .voice {
                selectedTab = .list
            }
        }
        .onChange(of: trip.startedAt) { oldValue, newValue in
            // If trip just became inactive and we're on voice tab, switch to list
            if !isTripActive && selectedTab == .voice {
                selectedTab = .list
            }
        }
        .onChange(of: trip.isTripEnded) { oldValue, newValue in
            // If trip just ended and we're on voice tab, switch to list
            if newValue && selectedTab == .voice {
                selectedTab = .list
            }
        }
        .onChange(of: selectedTab) { oldValue, newValue in
            if newValue == .voice {
                Task {
                    await requestSpeechAuthorizationIfNeeded()
                }
            } else {
                speechRecognizer.stopListening()
            }
        }
        .onChange(of: speechRecognizer.isListening) { oldValue, newValue in
            // When listening stops, process the final recognized text
            if oldValue == true && newValue == false {
                // Small delay to ensure we get the final text
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    processRecognizedText(speechRecognizer.recognizedText)
                }
            }
        }
        .overlay {
            if showVoiceMatchConfirmation, let region = lastMatchedRegion {
                VoiceConfirmationDialog(
                    region: region,
                    onAdd: {
                      confirmAddRegion(region, usingTab: .voice)
                    },
                    onCancel: {
                        showVoiceMatchConfirmation = false
                        lastMatchedRegion = nil
                    },
                    skipConfirmation: Binding(
                        get: { trip.skipVoiceConfirmation },
                        set: { newValue in
                            trip.skipVoiceConfirmation = newValue
                            try? modelContext.save()
                        }
                    )
                )
            }
        }
    }

    private var header: some View {
        VStack(spacing: 16) {
//            Text(trip.name)
//                .font(.system(.title2, design: .rounded))
//                .fontWeight(.bold)
//                .foregroundStyle(Color.Theme.primaryBlue)

          // Map view
          RegionMapView(
              country: visibleCountry,
              foundRegionIDs: trip.foundRegionIDs,
              namespace: mapNamespace,
              showFullScreen: $showFullScreenMap,
              locationManager: locationManager
          )
          .frame(height: 150)
          .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
          .padding(.horizontal, 32)
          
            HStack(spacing: 24) {
                summaryChip(title: "Found", value: "\(trip.foundRegionIDs.count)")
              
                // Calculate remaining based on enabled countries only
                let enabledRegions = PlateRegion.all.filter { trip.enabledCountries.contains($0.country) }
                summaryChip(title: "Remaining", value: "\(enabledRegions.count - trip.foundRegionIDs.count)")
            }
            
           
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.Theme.cardBackground)
                .padding(.horizontal, 12)
        )
        .padding(.top, 6)
        .padding(.bottom, 6)
    }

    private func summaryChip(title: String, value: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(.title, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(Color.Theme.primaryBlue)
            Text(title.uppercased())
                .font(.system(.caption, design: .rounded))
                .fontWeight(.medium)
                .foregroundStyle(Color.Theme.softBrown)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.Theme.background)
        )
    }

  
  private var regionListOriginal: some View {
         List {
             ForEach(PlateRegion.groupedByCountry(), id: \.country) { group in
                 Section(group.country.rawValue) {
                     ForEach(group.regions) { region in
                         RegionCellView(
                             region: region,
                             isSelected: trip.hasFound(regionID: region.id),
                             toggleAction: { toggle(regionID: region.id) }
                         )
                         .listRowBackground(Color.Theme.cardBackground)
                     }
                 }
             }
         }
         .listStyle(.insetGrouped)
         .scrollContentBackground(.hidden)
         .background(Color.Theme.background)
     }
  
    private var regionList: some View {
        // Filter regions to only show enabled countries
        let enabledCountries = trip.enabledCountries
        let filteredGroups = PlateRegion.groupedByCountry().filter { enabledCountries.contains($0.country) }
        
        return List {
            ForEach(filteredGroups, id: \.country) { group in
                Section() {
                    ForEach(group.regions) { region in
                        RegionCellView(
                            region: region,
                            isSelected: trip.hasFound(regionID: region.id),
                            toggleAction: { toggle(regionID: region.id) },
                            isDisabled: !isTripActive
                        )
                        .listRowBackground(Color.Theme.cardBackground)
                        .onAppear {
                            // Update visible country when scrolling to this section
                            withAnimation(.easeInOut(duration: 0.3)) {
                                visibleCountry = group.country
                            }
                        }
                    }
                } header: {
                    Text(group.country.rawValue)
                        .font(.headline)
                        .foregroundColor(Color.Theme.primaryBlue)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.Theme.background)
                        .listRowInsets(EdgeInsets())
                        .onAppear {
                            // Update visible country when section header appears
                            withAnimation(.easeInOut(duration: 0.3)) {
                                visibleCountry = group.country
                            }
                        }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(Color.Theme.background)
    }
    
    // Computed property to check if trip is active (started but not ended)
    private var isTripActive: Bool {
        trip.startedAt != nil && !trip.isTripEnded
    }
  
  private func setFound(regionID: String, usingTab: Trip.inputUsedToFindRegion) {
    FeedbackService.shared.actionSuccess()
    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
        trip.setFound(
            regionID: regionID,
            usingTab: usingTab,
            foundBy: authService.currentUser?.id,
            location: locationManager.location
        )
    }

    do {
        try modelContext.save()
    } catch {
        FeedbackService.shared.actionError()
        assertionFailure("Failed to save trip update: \(error)")
    }
  }
  
  
  private func setNotFound(regionID: String, usingTab: Trip.inputUsedToFindRegion) {
    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
        trip.setNotFound(
            regionID: regionID,
            usingTab: usingTab,
            foundBy: authService.currentUser?.id,
            location: locationManager.location
        )
    }

    do {
        try modelContext.save()
    } catch {
        assertionFailure("Failed to save trip update: \(error)")
    }
  }

    private func toggle(regionID: String) {
        // Don't allow toggling if trip is not active
        guard isTripActive else { return }
        
        FeedbackService.shared.toggleRegion()
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            trip.toggle(
                regionID: regionID,
                usingTab: .list,
                foundBy: authService.currentUser?.id,
                location: locationManager.location
            )
        }

        do {
            try modelContext.save()
        } catch {
            FeedbackService.shared.actionError()
            assertionFailure("Failed to save trip update: \(error)")
        }
    }

    private var voiceCaptureView: some View {
        VStack(spacing: 32) {
            // Microphone button - push and hold
            ZStack {
                Circle()
                    .fill(speechRecognizer.isListening ? Color.Theme.primaryBlue : Color.Theme.cardBackground)
                    .frame(width: 100, height: 100)
                    .shadow(color: Color.black.opacity(0.15), radius: 15, x: 0, y: 8)
                
                if speechRecognizer.isListening {
                    Circle()
                        .stroke(Color.Theme.accentYellow, lineWidth: 4)
                        .frame(width: 120, height: 120)
                        .opacity(0.6)
                        .scaleEffect(speechRecognizer.isListening ? 1.1 : 1.0)
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: speechRecognizer.isListening)
                }
                
                Image(systemName: speechRecognizer.isListening ? "mic.fill" : "mic.slash.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(speechRecognizer.isListening ? Color.white : Color.Theme.primaryBlue)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if isTripActive && !speechRecognizer.isListening && speechRecognizer.authorizationStatus == .authorized {
                            FeedbackService.shared.startRecording()
                            speechRecognizer.startListening()
                        }
                    }
                    .onEnded { _ in
                        if speechRecognizer.isListening {
                            speechRecognizer.stopListening()
                        }
                    }
            )
            .disabled(!isTripActive || speechRecognizer.authorizationStatus != .authorized)
            
            // Status text
            VStack(spacing: 12) {
                if speechRecognizer.authorizationStatus == .notDetermined || speechRecognizer.authorizationStatus == .denied {
                    Text("Speech Recognition Needed")
                        .font(.system(.title2, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                    
                    Text("Please enable speech recognition in Settings to use voice input.")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Button("Open Settings") {
                        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(settingsURL)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(Color.Theme.primaryBlue)
                    )
                    .foregroundStyle(Color.white)
                    .font(.system(.headline, design: .rounded))
                } else if speechRecognizer.authorizationStatus == .authorized {
                    Text(speechRecognizer.isListening ? "Listening..." : "Hold to Talk")
                        .font(.system(.title2, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                    
                    // Always show the recognized text
                    VStack(spacing: 8) {
                        Text("Heard:")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                        
                        ScrollView {
                            Text(speechRecognizer.recognizedText.isEmpty ? "No speech detected yet..." : speechRecognizer.recognizedText)
                                .font(.system(.body, design: .rounded))
                                .fontWeight(.medium)
                                .foregroundStyle(speechRecognizer.recognizedText.isEmpty ? Color.Theme.softBrown.opacity(0.6) : Color.Theme.primaryBlue)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .multilineTextAlignment(.leading)
                                .padding()
                        }
                        .frame(maxHeight: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.Theme.cardBackground)
                        )
                        .padding(.horizontal)
                    }
                    
                    if let errorMessage = speechRecognizer.errorMessage {
                        Text(errorMessage)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }
                } else {
                    Text("Requesting Permission...")
                        .font(.system(.title2, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 12)
        .background(Color.Theme.background)
        .task {
            await requestSpeechAuthorizationIfNeeded()
        }
    }
    
    
    private func requestSpeechAuthorizationIfNeeded() async {
        if speechRecognizer.authorizationStatus == .notDetermined {
            await speechRecognizer.requestAuthorization()
        }
    }
    
    private func processRecognizedText(_ text: String) {
        // Don't process if trip is not active
        guard isTripActive else { return }
        
        let normalizedText = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else { return }
        
        // Prevent processing the same text multiple times
        if normalizedText == lastProcessedText {
            print("⏭️ [Speech Match] Skipping duplicate text: '\(normalizedText)'")
            return
        }
        lastProcessedText = normalizedText
        
        // Normalize whitespace - replace multiple spaces with single space
        let cleanedText = normalizedText.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        
        // Split text into words for better matching
        let words = cleanedText.components(separatedBy: " ").filter { !$0.isEmpty }
        
        print("🔍 [Speech Match] Processing recognized text: '\(cleanedText)'")
        print("🔍 [Speech Match] Words extracted: \(words)")
        
        // Try to find a matching region - prioritize exact matches and better matches
        var bestMatch: PlateRegion?
        var bestMatchScore = 0
        
        // Only search in enabled countries
        let enabledCountries = trip.enabledCountries
        let enabledRegions = PlateRegion.all.filter { enabledCountries.contains($0.country) }
        
        for region in enabledRegions {
            let normalizedRegionName = region.name.lowercased()
            let regionWords = normalizedRegionName.components(separatedBy: " ").filter { !$0.isEmpty }
            
            // Check for exact match (highest priority)
            if cleanedText == normalizedRegionName {
                print("✅ [Speech Match] EXACT MATCH: '\(cleanedText)' == '\(normalizedRegionName)' -> \(region.name)")
                addRegionIfNotFound(region)
                return
            }
            
            // Check if the recognized text contains the full region name
            if cleanedText.contains(normalizedRegionName) {
                print("✅ [Speech Match] CONTAINS MATCH: '\(cleanedText)' contains '\(normalizedRegionName)' -> \(region.name)")
                addRegionIfNotFound(region)
                return
            }
            
            // For multi-word regions, we need stricter matching
            // Check if all words match exactly or very closely
            if regionWords.count > 1 {
                // For multi-word regions, require ALL words to match
                // Use a fresh copy of words for each region check
                var availableWords = words
                var matchedWords = 0
                var matchedWordDetails: [String] = []
                var allWordsMatched = true
                
                for regionWord in regionWords {
                    var foundMatch = false
                    var matchType = ""
                    var matchedWord: String? = nil
                    
                    // Find the first available word that matches
                    for (index, word) in availableWords.enumerated() {
                        // Exact match (preferred)
                        if word == regionWord {
                            foundMatch = true
                            matchType = "exact"
                            matchedWord = word
                            availableWords.remove(at: index)
                            break
                        }
                    }
                    
                    // If no exact match, try fuzzy matching only for very similar words
                    if !foundMatch {
                        for (index, word) in availableWords.enumerated() {
                            // Only allow fuzzy matching if words are very similar (same length or very close)
                            let lengthDiff = abs(word.count - regionWord.count)
                            if lengthDiff <= 2 && word.count >= 3 && regionWord.count >= 3 {
                                // Check if first 4 characters match (more strict than 3)
                                let wordPrefix = String(word.prefix(min(4, word.count)))
                                let regionPrefix = String(regionWord.prefix(min(4, regionWord.count)))
                                
                                if wordPrefix == regionPrefix {
                                    foundMatch = true
                                    matchType = "fuzzy-prefix"
                                    matchedWord = word
                                    availableWords.remove(at: index)
                                    break
                                }
                            }
                        }
                    }
                    
                    if foundMatch {
                        matchedWords += 1
                        matchedWordDetails.append("'\(regionWord)' (matched via \(matchType) with '\(matchedWord ?? "")')")
                    } else {
                        allWordsMatched = false
                        matchedWordDetails.append("'\(regionWord)' (NO MATCH)")
                    }
                }
                
                // Only consider it a match if ALL words matched
                if allWordsMatched && matchedWords == regionWords.count {
                    print("🔍 [Speech Match] Candidate: \(region.name) - Matched \(matchedWords)/\(regionWords.count) words")
                    print("   Details: \(matchedWordDetails.joined(separator: ", "))")
                    
                    if matchedWords > bestMatchScore {
                        bestMatch = region
                        bestMatchScore = matchedWords
                        print("   ⭐ New best match (multi-word): \(region.name) with score \(bestMatchScore)")
                    }
                } else if matchedWords > 0 {
                    print("⚠️ [Speech Match] Partial: \(region.name) - Only matched \(matchedWords)/\(regionWords.count) words")
                    print("   Details: \(matchedWordDetails.joined(separator: ", "))")
                }
            } else {
                // Single word regions - use original logic but be more strict
                let regionWord = regionWords[0]
                var foundMatch = false
                var matchType = ""
                
                let wordMatches = words.contains { word in
                    // Exact match
                    if word == regionWord {
                        foundMatch = true
                        matchType = "exact"
                        return true
                    }
                    // Fuzzy match only if very similar
                    if word.count >= 3 && regionWord.count >= 3 {
                        let lengthDiff = abs(word.count - regionWord.count)
                        if lengthDiff <= 2 {
                            let wordPrefix = String(word.prefix(min(4, word.count)))
                            let regionPrefix = String(regionWord.prefix(min(4, regionWord.count)))
                            if wordPrefix == regionPrefix {
                                foundMatch = true
                                matchType = "fuzzy-prefix"
                                return true
                            }
                        }
                    }
                    return false
                }
                
                if wordMatches {
                    if 1 > bestMatchScore {
                        bestMatch = region
                        bestMatchScore = 1
                        print("   ⭐ New best match (single word): \(region.name)")
                    }
                }
            }
        }
        
        // If we found a good match, use it
        if let match = bestMatch {
            print("✅ [Speech Match] FINAL MATCH: \(match.name) with score \(bestMatchScore)")
            addRegionIfNotFound(match)
        } else {
            print("❌ [Speech Match] NO MATCH FOUND for '\(cleanedText)'")
        }
    }
    
    private func addRegionIfNotFound(_ region: PlateRegion) {
        // Only add if not already found
        if !trip.hasFound(regionID: region.id) {
            lastMatchedRegion = region
            
            // Check if user wants to skip confirmation
            if trip.skipVoiceConfirmation {
                // Auto-add without confirmation
              confirmAddRegion(region, usingTab: .voice)
            } else {
                // Show confirmation popup
                showVoiceMatchConfirmation = true
            }
        } else {
            print("ℹ️ [Speech Match] Region \(region.name) already found, skipping")
        }
    }
    
  private func confirmAddRegion(_ region: PlateRegion, usingTab: Trip.inputUsedToFindRegion) {
        setFound(regionID: region.id, usingTab: usingTab)
        showVoiceMatchConfirmation = false
        lastMatchedRegion = nil
        
        // Clear recognized text and reset processed text after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            speechRecognizer.recognizedText = ""
            lastProcessedText = ""
        }
    }

    private var customTabBar: some View {
//          VStack(spacing: 16) {
//              Image(systemName: "stop.circle.fill")
//                  .font(.system(size: 64))
//                  .foregroundStyle(Color.red.opacity(0.5))
//              Text("Trip Ended")
//                  .font(.system(.title2, design: .rounded))
//                  .fontWeight(.semibold)
//                  .foregroundStyle(Color.Theme.primaryBlue)
//              Text("This trip has been ended. You can no longer add states.")
//                  .font(.system(.body, design: .rounded))
//                  .foregroundStyle(Color.Theme.softBrown)
//                  .multilineTextAlignment(.center)
//                  .padding(.horizontal)
//          }
//          .frame(maxWidth: .infinity, maxHeight: .infinity)
        HStack(spacing: 16) {
            ForEach(Tab.allCases) { tab in
                let isTabDisabled = !isTripActive
                Button {
                    // Prevent switching to tabs if trip is not active
                    if isTabDisabled {
                        return
                    }
                    FeedbackService.shared.selectionChange()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 20, weight: .semibold))

                        Text(tab.title)
                            .font(.system(.headline, design: .rounded))
                            .fontWeight(.semibold)
                    }
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(selectedTab == tab ? Color.Theme.primaryBlue : Color.Theme.cardBackground)
                    )
                    .foregroundStyle(selectedTab == tab ? Color.white : Color.Theme.primaryBlue)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(selectedTab == tab ? Color.Theme.accentYellow.opacity(0.3) : Color.clear, lineWidth: 3)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isTabDisabled)
                .opacity(isTabDisabled ? 0.5 : 1.0)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.Theme.cardBackground)
                .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: -3)
                .padding(.horizontal, 12)
                .padding(.vertical, 12	)
        )
    }
  
  private var voiceCapturePlaceholder: some View {
    VStack(spacing: 24) {
      Image(systemName: Tab.voice.systemImage)
        .font(.system(size: 72))
        .foregroundStyle(Color.Theme.accentYellow)
        .padding()
        .background(
          Circle()
            .fill(Color.Theme.cardBackground)
            .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 8)
        )
      
      Text("Voice Coming Soon")
        .font(.system(.title2, design: .rounded))
        .fontWeight(.bold)
        .foregroundStyle(Color.Theme.primaryBlue)
      
      Text("Soon you will be able to log plates hands-free by simply saying the state or province you spot.")
        .font(.system(.body, design: .rounded))
        .foregroundStyle(Color.Theme.softBrown)
        .multilineTextAlignment(.center)
        .padding(.horizontal)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .padding(.top, 20)
  }

}

private struct RegionCellView: View {
    let region: PlateRegion
    let isSelected: Bool
    var toggleAction: () -> Void
    var isDisabled: Bool = false

    var body: some View {
        Button {
            if !isDisabled {
                toggleAction()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.Theme.primaryBlue)

                VStack(alignment: .leading, spacing: 4) {
                    Text(region.name)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.medium)
                        .foregroundStyle(Color.Theme.primaryBlue)

                    Text(region.country.rawValue)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? Color.Theme.accentYellow : Color.Theme.softBrown.opacity(0.4))
                    .scaleEffect(isSelected ? 1.05 : 1.0)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1.0)
    }
}

// Custom confirmation dialog for voice recognition
private struct VoiceConfirmationDialog: View {
    let region: PlateRegion
    let onAdd: () -> Void
    let onCancel: () -> Void
    @Binding var skipConfirmation: Bool
    
    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    onCancel()
                }
            
            // Dialog box
            VStack(spacing: 0) {
                VStack(spacing: 20) {
                    Text("Hey, we heard the following \(region.country == .canada ? "province" : "state"):")
                        .font(.system(.title3, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                        .multilineTextAlignment(.center)
                    
                    Text(region.name)
                        .font(.system(.largeTitle, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 4)
                    
                    Text("Add this to the list of license plates found?")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 32)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                
                Divider()
                    .background(Color.Theme.softBrown.opacity(0.2))
                
                VStack(spacing: 16) {
                    // Don't show again checkbox
                    Button {
                        skipConfirmation.toggle()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: skipConfirmation ? "checkmark.square.fill" : "square")
                                .font(.system(size: 20))
                                .foregroundStyle(skipConfirmation ? Color.Theme.primaryBlue : Color.Theme.softBrown)
                            
                            Text("Don't show this again")
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(Color.Theme.primaryBlue)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 16)
                    
                    // Action buttons
                    HStack(spacing: 16) {
                        Button {
                            onCancel()
                        } label: {
                            Text("Cancel")
                                .font(.system(.headline, design: .rounded))
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.Theme.primaryBlue)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Color.Theme.cardBackground)
                                )
                        }
                        
                        Button {
                            onAdd()
                        } label: {
                            Text("Add")
                                .font(.system(.headline, design: .rounded))
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Color.Theme.primaryBlue)
                                )
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: 320)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.Theme.cardBackground)
                    .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 10)
            )
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
}

// Settings View for current trip
private struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var trip: Trip
    let modelContext: ModelContext
    
    enum SettingsSection: String, CaseIterable {
        case tripInfo = "Trip Info"
        case gameSettings = "Game Settings"
        case trackingPrivacy = "Tracking & Privacy"
        case voice = "Voice"
        
        var id: String { rawValue }
    }
    
    @EnvironmentObject var authService: FirebaseAuthService
    @StateObject private var locationManager = LocationManager()
    
    @State private var showEndTripConfirmation = false
    @State private var showResetConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var isEditingTripName = false
    @State private var editingTripName: String = ""
    
    private var isTripCreator: Bool {
        guard let currentUserID = authService.currentUser?.id else { return false }
        return trip.createdBy == currentUserID
    }
    
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
        }
        .background(Color.Theme.background)
    }
    
    private var tripInfoSettings: some View {
        Group {
            // Edit Trip Name
            SettingEditableTextRow(
                title: "Trip Name",
                value: Binding(
                    get: { trip.name },
                    set: { newValue in
                        trip.name = newValue
                        trip.lastUpdated = Date.now
                        try? modelContext.save()
                    }
                ),
                placeholder: "Enter trip name",
                isDisabled: !isTripCreator,
                onSave: {
                    try? modelContext.save()
                },
                onCancel: {}
            )
            
            Divider()
            
            // Created At Date
            SettingInfoRow(
                title: "Created",
                value: dateFormatter.string(from: trip.createdAt)
            )
            
            Divider()
            
            // Start Date
            if let startedAt = trip.startedAt {
                SettingInfoRow(
                    title: "Started",
                    value: dateFormatter.string(from: startedAt)
                )
            } else {
                Button {
                    trip.startedAt = Date.now
                    trip.lastUpdated = Date.now
                    try? modelContext.save()
                } label: {
                    HStack {
                        Text("Start Trip")
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
                .disabled(!isTripCreator)
                .opacity(isTripCreator ? 1.0 : 0.5)
            }
            
            Divider()
            
            // End Trip Button
            if trip.startedAt != nil && !trip.isTripEnded {
                Button {
                    showEndTripConfirmation = true
                } label: {
                    HStack {
                        Text("End Trip")
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
                .disabled(!isTripCreator)
                
                Divider()
            } else if let endedAt = trip.tripEndedAt {
              SettingInfoRow(
                  title: "Ended",
                  value: dateFormatter.string(from: endedAt)
              )
            }
            
            // Reset Button
            Button {
                showResetConfirmation = true
            } label: {
                HStack {
                    Text("Reset Trip")
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                    Spacer()
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)
            .disabled(!isTripCreator)
            
            Divider()
            
            // Delete Button
            Button {
                showDeleteConfirmation = true
            } label: {
                HStack {
                    Text("Delete Trip")
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(.red)
                    Spacer()
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)
            .disabled(!isTripCreator)
        }
        .alert("End Trip", isPresented: $showEndTripConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("End Trip", role: .destructive) {
                trip.isTripEnded = true
                trip.tripEndedAt = Date.now
                trip.tripEndedBy = authService.currentUser?.id
                trip.lastUpdated = Date.now
                try? modelContext.save()
            }
        } message: {
            Text("This will stop the game. You won't be able to add states in this trip anymore.")
        }
        .alert("Reset Trip", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                // Reset all trip settings except name
                trip.startedAt = nil
                trip.isTripEnded = false
                trip.tripEndedAt = nil
                trip.tripEndedBy = nil
                trip.foundRegions = []
                trip.skipVoiceConfirmation = false
                trip.holdToTalk = true
                trip.saveLocationWhenMarkingPlates = true
                trip.showMyLocationOnLargeMap = true
                trip.trackMyLocationDuringTrip = true
                trip.showMyActiveTripOnLargeMap = true
                trip.showMyActiveTripOnSmallMap = true
                trip.lastUpdated = Date.now
                // TODO: Add log entry for reset
                try? modelContext.save()
            }
        } message: {
            Text("This will reset all trip settings but the trip name. Everything will be reset, including Start Date, which will not auto start. Any logs will be erased, other than a log stating it was reset.")
        }
        .alert("Delete Trip", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                modelContext.delete(trip)
                try? modelContext.save()
                dismiss()
            }
        } message: {
            Text("This will delete the trip and all scores will be removed.")
        }
    }
    
    private var gameSettings: some View {
        Group {
            let canEditCountries = trip.startedAt == nil // Countries can only be edited before trip starts
            
            // Countries selection
            VStack(alignment: .leading, spacing: 12) {
                Text("Countries to Include")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .padding(.bottom, 4)
                
                CountryCheckboxRow(
                    title: "United States",
                    isOn: Binding(
                        get: { trip.enabledCountries.contains(.unitedStates) },
                        set: { newValue in
                            if newValue {
                                if !trip.enabledCountries.contains(.unitedStates) {
                                    trip.enabledCountries.append(.unitedStates)
                                }
                            } else {
                                trip.enabledCountries.removeAll { $0 == .unitedStates }
                            }
                            trip.lastUpdated = Date.now
                            try? modelContext.save()
                        }
                    )
                )
                .disabled(!canEditCountries)
                .opacity(canEditCountries ? 1.0 : 0.5)
                
                CountryCheckboxRow(
                    title: "Canada",
                    isOn: Binding(
                        get: { trip.enabledCountries.contains(.canada) },
                        set: { newValue in
                            if newValue {
                                if !trip.enabledCountries.contains(.canada) {
                                    trip.enabledCountries.append(.canada)
                                }
                            } else {
                                trip.enabledCountries.removeAll { $0 == .canada }
                            }
                            trip.lastUpdated = Date.now
                            try? modelContext.save()
                        }
                    )
                )
                .disabled(!canEditCountries)
                .opacity(canEditCountries ? 1.0 : 0.5)
                
                CountryCheckboxRow(
                    title: "Mexico",
                    isOn: Binding(
                        get: { trip.enabledCountries.contains(.mexico) },
                        set: { newValue in
                            if newValue {
                                if !trip.enabledCountries.contains(.mexico) {
                                    trip.enabledCountries.append(.mexico)
                                }
                            } else {
                                trip.enabledCountries.removeAll { $0 == .mexico }
                            }
                            trip.lastUpdated = Date.now
                            try? modelContext.save()
                        }
                    )
                )
                .disabled(!canEditCountries)
                .opacity(canEditCountries ? 1.0 : 0.5)
            }
        }
    }
    
    private var trackingPrivacySettings: some View {
        Group {
            let locationAuthorized = locationManager.authorizationStatus == .authorizedWhenInUse || locationManager.authorizationStatus == .authorizedAlways
            let canEditTracking = !trip.isTripEnded // Tracking settings can be edited while active, but not after ended
            
            SettingToggleRow(
                title: "Save location when marking plates",
                description: "Store location data when you mark a plate as found",
                isOn: Binding(
                    get: { trip.saveLocationWhenMarkingPlates },
                    set: { newValue in
                        trip.saveLocationWhenMarkingPlates = newValue
                        trip.lastUpdated = Date.now
                        try? modelContext.save()
                    }
                )
            )
            .disabled(!locationAuthorized || !canEditTracking)
            .opacity((locationAuthorized && canEditTracking) ? 1.0 : 0.5)
            
            Divider()
            
            SettingToggleRow(
                title: "Show my location on large map",
                description: "Display your current location on the full-screen map",
                isOn: Binding(
                    get: { trip.showMyLocationOnLargeMap },
                    set: { newValue in
                        trip.showMyLocationOnLargeMap = newValue
                        trip.lastUpdated = Date.now
                        try? modelContext.save()
                    }
                )
            )
            .disabled(!canEditTracking)
            .opacity(canEditTracking ? 1.0 : 0.5)
            
            Divider()
            
            SettingToggleRow(
                title: "Track my location during trip",
                description: "Continuously track your location while a trip is active",
                isOn: Binding(
                    get: { trip.trackMyLocationDuringTrip },
                    set: { newValue in
                        trip.trackMyLocationDuringTrip = newValue
                        trip.lastUpdated = Date.now
                        try? modelContext.save()
                    }
                )
            )
            .disabled(!canEditTracking)
            .opacity(canEditTracking ? 1.0 : 0.5)
            
            Divider()
            
            SettingToggleRow(
                title: "Show my active trip on the large map",
                description: "Display your active trip on the full-screen map",
                isOn: Binding(
                    get: { trip.showMyActiveTripOnLargeMap },
                    set: { newValue in
                        trip.showMyActiveTripOnLargeMap = newValue
                        trip.lastUpdated = Date.now
                        try? modelContext.save()
                    }
                )
            )
            .disabled(!trip.trackMyLocationDuringTrip || !canEditTracking)
            .opacity((trip.trackMyLocationDuringTrip && canEditTracking) ? 1.0 : 0.5)
            
            Divider()
            
            SettingToggleRow(
                title: "Show my active trip on the small map",
                description: "Display your active trip on the small map",
                isOn: Binding(
                    get: { trip.showMyActiveTripOnSmallMap },
                    set: { newValue in
                        trip.showMyActiveTripOnSmallMap = newValue
                        trip.lastUpdated = Date.now
                        try? modelContext.save()
                    }
                )
            )
            .disabled(!trip.trackMyLocationDuringTrip || !canEditTracking)
            .opacity((trip.trackMyLocationDuringTrip && canEditTracking) ? 1.0 : 0.5)
        }
    }
    
    private var voiceSettings: some View {
        Group {
            let canEditSettings = trip.startedAt == nil // Can only edit if trip hasn't started
            
            SettingToggleRow(
                title: "Skip Voice Confirmation",
                description: "Automatically add license plates without confirmation when using Voice",
                isOn: Binding(
                    get: { trip.skipVoiceConfirmation },
                    set: { newValue in
                        trip.skipVoiceConfirmation = newValue
                        trip.lastUpdated = Date.now
                        try? modelContext.save()
                    }
                )
            )
            .disabled(!canEditSettings)
            .opacity(canEditSettings ? 1.0 : 0.5)
          if false {
            SettingToggleRow(
              title: "Hold to Talk",
              description: "Press and hold the microphone button to record. If disabled the system will listen until you hit stop.",
              isOn: Binding(
                get: { trip.holdToTalk },
                set: { newValue in
                  trip.holdToTalk = newValue
                  trip.lastUpdated = Date.now
                  try? modelContext.save()
                }
              )
            )
            .disabled(!canEditSettings)
            .opacity(canEditSettings ? 1.0 : 0.5)
          }
        }
    }
}

// Country checkbox row component for trip settings
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

// Full screen map view with location support
private struct FullScreenMapView: View {
    let country: PlateRegion.Country
    let foundRegionIDs: [String]
    @ObservedObject var locationManager: LocationManager
    let namespace: Namespace.ID
    @Binding var isPresented: Bool
    
    @State private var mapCameraPosition: MapCameraPosition
    
    init(country: PlateRegion.Country, foundRegionIDs: [String], locationManager: LocationManager, namespace: Namespace.ID, isPresented: Binding<Bool>) {
        self.country = country
        self.foundRegionIDs = foundRegionIDs
        self.locationManager = locationManager
        self.namespace = namespace
        self._isPresented = isPresented
        
        // Initialize map region based on country
        let initialRegion: MKCoordinateRegion
        switch country {
        case .unitedStates:
            initialRegion = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 40.8283, longitude: -106.5795),
                span: MKCoordinateSpan(latitudeDelta: 50, longitudeDelta: 100)
            )
        case .canada:
            initialRegion = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 56.1304, longitude: -106.3468),
                span: MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 60)
            )
        case .mexico:
            initialRegion = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 23.6345, longitude: -102.5528),
                span: MKCoordinateSpan(latitudeDelta: 15, longitudeDelta: 20)
            )
        }
        
        _mapCameraPosition = State(initialValue: .region(initialRegion))
    }
    
    private var regions: [PlateRegion] {
        PlateRegion.all.filter { $0.country == country }
    }
    
    private var coordinateForRegion: (PlateRegion) -> CLLocationCoordinate2D {
        { region in
            let coordinates: [String: CLLocationCoordinate2D] = [
                // United States
                "us-al": CLLocationCoordinate2D(latitude: 32.806671, longitude: -86.791130),
                "us-ak": CLLocationCoordinate2D(latitude: 61.370716, longitude: -152.404419),
                "us-az": CLLocationCoordinate2D(latitude: 33.729759, longitude: -111.431221),
                "us-ar": CLLocationCoordinate2D(latitude: 34.969704, longitude: -92.373123),
                "us-ca": CLLocationCoordinate2D(latitude: 36.116203, longitude: -119.681564),
                "us-co": CLLocationCoordinate2D(latitude: 39.059811, longitude: -105.311104),
                "us-ct": CLLocationCoordinate2D(latitude: 41.597782, longitude: -72.755371),
                "us-de": CLLocationCoordinate2D(latitude: 39.318523, longitude: -75.507141),
                "us-fl": CLLocationCoordinate2D(latitude: 27.766279, longitude: -81.686783),
                "us-ga": CLLocationCoordinate2D(latitude: 33.040619, longitude: -83.643074),
                "us-hi": CLLocationCoordinate2D(latitude: 21.094318, longitude: -157.498337),
                "us-id": CLLocationCoordinate2D(latitude: 44.240459, longitude: -114.478828),
                "us-il": CLLocationCoordinate2D(latitude: 40.349457, longitude: -88.986137),
                "us-in": CLLocationCoordinate2D(latitude: 39.849426, longitude: -86.258278),
                "us-ia": CLLocationCoordinate2D(latitude: 42.011539, longitude: -93.210526),
                "us-ks": CLLocationCoordinate2D(latitude: 38.526600, longitude: -96.726486),
                "us-ky": CLLocationCoordinate2D(latitude: 37.668140, longitude: -84.670067),
                "us-la": CLLocationCoordinate2D(latitude: 31.169546, longitude: -91.867805),
                "us-me": CLLocationCoordinate2D(latitude: 44.323535, longitude: -69.765261),
                "us-md": CLLocationCoordinate2D(latitude: 39.063946, longitude: -76.802101),
                "us-ma": CLLocationCoordinate2D(latitude: 42.230171, longitude: -71.530106),
                "us-mi": CLLocationCoordinate2D(latitude: 43.326618, longitude: -84.536095),
                "us-mn": CLLocationCoordinate2D(latitude: 45.694454, longitude: -93.900192),
                "us-ms": CLLocationCoordinate2D(latitude: 32.741646, longitude: -89.678696),
                "us-mo": CLLocationCoordinate2D(latitude: 38.456085, longitude: -92.288368),
                "us-mt": CLLocationCoordinate2D(latitude: 46.921925, longitude: -110.454353),
                "us-ne": CLLocationCoordinate2D(latitude: 41.125370, longitude: -98.268082),
                "us-nv": CLLocationCoordinate2D(latitude: 38.313515, longitude: -117.055374),
                "us-nh": CLLocationCoordinate2D(latitude: 43.452492, longitude: -71.563896),
                "us-nj": CLLocationCoordinate2D(latitude: 40.298904, longitude: -74.521011),
                "us-nm": CLLocationCoordinate2D(latitude: 34.840515, longitude: -106.248482),
                "us-ny": CLLocationCoordinate2D(latitude: 42.165726, longitude: -74.948051),
                "us-nc": CLLocationCoordinate2D(latitude: 35.630066, longitude: -79.806419),
                "us-nd": CLLocationCoordinate2D(latitude: 47.528912, longitude: -99.784012),
                "us-oh": CLLocationCoordinate2D(latitude: 40.388783, longitude: -82.764915),
                "us-ok": CLLocationCoordinate2D(latitude: 35.565342, longitude: -96.928917),
                "us-or": CLLocationCoordinate2D(latitude: 44.572021, longitude: -122.070938),
                "us-pa": CLLocationCoordinate2D(latitude: 40.590752, longitude: -77.209755),
                "us-ri": CLLocationCoordinate2D(latitude: 41.680893, longitude: -71.51178),
                "us-sc": CLLocationCoordinate2D(latitude: 33.856892, longitude: -80.945007),
                "us-sd": CLLocationCoordinate2D(latitude: 44.299782, longitude: -99.438828),
                "us-tn": CLLocationCoordinate2D(latitude: 35.747845, longitude: -86.692345),
                "us-tx": CLLocationCoordinate2D(latitude: 31.054487, longitude: -97.563461),
                "us-ut": CLLocationCoordinate2D(latitude: 40.150032, longitude: -111.862434),
                "us-vt": CLLocationCoordinate2D(latitude: 44.045876, longitude: -72.710686),
                "us-va": CLLocationCoordinate2D(latitude: 37.769337, longitude: -78.169968),
                "us-wa": CLLocationCoordinate2D(latitude: 47.400902, longitude: -121.490494),
                "us-wv": CLLocationCoordinate2D(latitude: 38.491226, longitude: -80.954453),
                "us-wi": CLLocationCoordinate2D(latitude: 44.268543, longitude: -89.616508),
                "us-wy": CLLocationCoordinate2D(latitude: 42.755966, longitude: -107.302490),
                "us-dc": CLLocationCoordinate2D(latitude: 38.907192, longitude: -77.036873),
                "us-pr": CLLocationCoordinate2D(latitude: 18.220833, longitude: -66.590149),
                "us-gu": CLLocationCoordinate2D(latitude: 13.444304, longitude: 144.793731),
                "us-vi": CLLocationCoordinate2D(latitude: 18.335765, longitude: -64.896335),
                "us-as": CLLocationCoordinate2D(latitude: -14.271000, longitude: -170.132217),
                "us-mp": CLLocationCoordinate2D(latitude: 17.330830, longitude: 145.384690),
                // Canada
                "ca-ab": CLLocationCoordinate2D(latitude: 53.933271, longitude: -116.576504),
                "ca-bc": CLLocationCoordinate2D(latitude: 53.726669, longitude: -127.647621),
                "ca-mb": CLLocationCoordinate2D(latitude: 53.760861, longitude: -98.813876),
                "ca-nb": CLLocationCoordinate2D(latitude: 46.565316, longitude: -66.461916),
                "ca-nl": CLLocationCoordinate2D(latitude: 53.135509, longitude: -57.660436),
                "ca-nt": CLLocationCoordinate2D(latitude: 64.825545, longitude: -124.845733),
                "ca-ns": CLLocationCoordinate2D(latitude: 44.682006, longitude: -63.744311),
                "ca-nu": CLLocationCoordinate2D(latitude: 70.299771, longitude: -83.107577),
                "ca-on": CLLocationCoordinate2D(latitude: 50.000000, longitude: -85.000000),
                "ca-pe": CLLocationCoordinate2D(latitude: 46.510712, longitude: -63.416813),
                "ca-qc": CLLocationCoordinate2D(latitude: 52.939916, longitude: -73.549136),
                "ca-sk": CLLocationCoordinate2D(latitude: 52.939916, longitude: -106.450864),
                "ca-yt": CLLocationCoordinate2D(latitude: 64.282327, longitude: -135.000000),
                // Mexico
                "mx-ags": CLLocationCoordinate2D(latitude: 21.885256, longitude: -102.291567),
                "mx-bcn": CLLocationCoordinate2D(latitude: 30.840634, longitude: -115.283758),
                "mx-bcs": CLLocationCoordinate2D(latitude: 26.044444, longitude: -111.666072),
                "mx-cam": CLLocationCoordinate2D(latitude: 19.830125, longitude: -90.534909),
                "mx-chp": CLLocationCoordinate2D(latitude: 16.756931, longitude: -93.129235),
                "mx-chh": CLLocationCoordinate2D(latitude: 28.632996, longitude: -106.069100),
                "mx-coa": CLLocationCoordinate2D(latitude: 27.058676, longitude: -101.706829),
                "mx-col": CLLocationCoordinate2D(latitude: 19.245234, longitude: -103.724087),
                "mx-dur": CLLocationCoordinate2D(latitude: 24.027720, longitude: -104.653176),
                "mx-gua": CLLocationCoordinate2D(latitude: 21.019015, longitude: -101.257359),
                "mx-gro": CLLocationCoordinate2D(latitude: 17.573988, longitude: -99.497688),
                "mx-hid": CLLocationCoordinate2D(latitude: 20.091143, longitude: -98.762387),
                "mx-jal": CLLocationCoordinate2D(latitude: 20.659699, longitude: -103.349609),
                "mx-mex": CLLocationCoordinate2D(latitude: 19.496873, longitude: -99.723267),
                "mx-mic": CLLocationCoordinate2D(latitude: 19.566519, longitude: -101.706829),
                "mx-mor": CLLocationCoordinate2D(latitude: 18.681305, longitude: -99.101350),
                "mx-nay": CLLocationCoordinate2D(latitude: 21.751384, longitude: -105.231098),
                "mx-nle": CLLocationCoordinate2D(latitude: 25.592172, longitude: -99.996194),
                "mx-oax": CLLocationCoordinate2D(latitude: 17.073184, longitude: -96.726588),
                "mx-pue": CLLocationCoordinate2D(latitude: 19.041440, longitude: -98.206273),
                "mx-que": CLLocationCoordinate2D(latitude: 20.588793, longitude: -100.389888),
                "mx-roo": CLLocationCoordinate2D(latitude: 19.181738, longitude: -88.479137),
                "mx-slp": CLLocationCoordinate2D(latitude: 22.156469, longitude: -100.985540),
                "mx-sin": CLLocationCoordinate2D(latitude: 25.172109, longitude: -107.801228),
                "mx-son": CLLocationCoordinate2D(latitude: 29.297019, longitude: -110.330925),
                "mx-tab": CLLocationCoordinate2D(latitude: 18.166850, longitude: -92.618927),
                "mx-tam": CLLocationCoordinate2D(latitude: 24.266940, longitude: -98.836275),
                "mx-tla": CLLocationCoordinate2D(latitude: 19.313923, longitude: -98.240447),
                "mx-ver": CLLocationCoordinate2D(latitude: 19.173773, longitude: -96.134224),
                "mx-yuc": CLLocationCoordinate2D(latitude: 20.684285, longitude: -89.094338),
                "mx-zac": CLLocationCoordinate2D(latitude: 23.293451, longitude: -102.700737),
                "mx-cmx": CLLocationCoordinate2D(latitude: 19.432608, longitude: -99.133209)
            ]
            return coordinates[region.id] ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        }
    }
    
    var body: some View {
        ZStack {
            // Full screen map
            Map(position: $mapCameraPosition) {
                // Region annotations
                ForEach(PlateRegion.all) { region in
                    Annotation(region.name, coordinate: coordinateForRegion(region)) {
                        Circle()
                            .fill(foundRegionIDs.contains(region.id) ? Color.Theme.accentYellow : Color.Theme.primaryBlue.opacity(0.6))
                            .frame(width: 16, height: 16)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 2)
                            )
                            .shadow(color: Color.black.opacity(0.3), radius: 3, x: 0, y: 2)
                    }
                }
                
                // User location annotation
                if let userLocation = locationManager.location,
                   locationManager.authorizationStatus == .authorizedWhenInUse || locationManager.authorizationStatus == .authorizedAlways {
                    Annotation("Your Location", coordinate: userLocation.coordinate) {
                        ZStack {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 20, height: 20)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: 3)
                                )
                            
                            Circle()
                                .fill(Color.green.opacity(0.3))
                                .frame(width: 32, height: 32)
                        }
                        .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                }
            }
            .mapStyle(AppPreferences.mapStyleFromPreference())
            .matchedGeometryEffect(id: "map", in: namespace)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .onAppear {
                // Start location updates if permission granted
                if locationManager.authorizationStatus == .authorizedWhenInUse || locationManager.authorizationStatus == .authorizedAlways {
                    locationManager.startUpdatingLocation()
                }
            }
            .onDisappear {
                locationManager.stopUpdatingLocation()
            }
            
            // Close button - positioned below safe area at top right
            GeometryReader { geometry in
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                isPresented = false
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(Color.Theme.primaryBlue)
                                .background(
                                    Circle()
                                        .fill(Color.white)
                                        .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
                                )
                        }
                        .safeAreaPadding(.all)
                        .padding(.trailing, 0)
                        .padding(.top, 32)
                    }
                    Spacer()
                }
            }
        }
        .background(
            Color(
                light: Color.black,
                dark: Color(red: 0.05, green: 0.05, blue: 0.05)
            ).ignoresSafeArea()
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
    }
}

// Map view showing regions for a specific country
private struct RegionMapView: View {
    let country: PlateRegion.Country
    let foundRegionIDs: [String]
    let namespace: Namespace.ID
    @Binding var showFullScreen: Bool
    @ObservedObject var locationManager: LocationManager
    
    @State private var mapRegion: MKCoordinateRegion
    
    init(country: PlateRegion.Country, foundRegionIDs: [String], namespace: Namespace.ID, showFullScreen: Binding<Bool>, locationManager: LocationManager) {
        self.country = country
        self.foundRegionIDs = foundRegionIDs
        self.namespace = namespace
        self._showFullScreen = showFullScreen
        self.locationManager = locationManager
        
        // Initialize map region based on country
        switch country {
          // Happened on full screen click.
        case .unitedStates:
            _mapRegion = State(initialValue: MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 40.8283, longitude: -106.5795),
                span: MKCoordinateSpan(latitudeDelta: 50, longitudeDelta: 50)
            ))
        case .canada:
            _mapRegion = State(initialValue: MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 56.1304, longitude: -106.3468),
                span: MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 60)
            ))
        case .mexico:
            _mapRegion = State(initialValue: MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 23.6345, longitude: -102.5528),
                span: MKCoordinateSpan(latitudeDelta: 15, longitudeDelta: 20)
            ))
        }
    }
    
    private var regionsForCurrentCountry: [PlateRegion] {
        PlateRegion.all.filter { $0.country == country }
    }
  
  private var regionsFound: [PlateRegion] {
    PlateRegion.all.filter { foundRegionIDs.contains($0.id)}
  }
    
    var body: some View {
        ZStack {
          
//          Map(initialPosition: .region(mapRegion)){
//              ForEach(regionsFound) { region in
//                Annotation(region.name, coordinate: coordinateForRegion(region)) {
//                  Circle()
//                      .fill(foundRegionIDs.contains(region.id) ? Color.Theme.accentYellow : Color.Theme.primaryBlue.opacity(0.6))
//                      .frame(width: 12, height: 12)
//                      .overlay(
//                          Circle()
//                              .stroke(Color.white, lineWidth: 2)
//                      )
//                      .shadow(color: Color.black.opacity(0.3), radius: 2, x: 0, y: 1)
//                }
//              }
//            }
          
          Map(coordinateRegion: $mapRegion, annotationItems: regionsFound) { region in
                MapAnnotation(coordinate: coordinateForRegion(region)) {
                    Circle()
                        .fill(foundRegionIDs.contains(region.id) ? Color.Theme.accentYellow : Color.Theme.primaryBlue.opacity(0.6))
                        .frame(width: 12, height: 12)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                        )
                        .shadow(color: Color.black.opacity(0.3), radius: 2, x: 0, y: 1)
                }
            }
            .mapStyle(AppPreferences.mapStyleFromPreference())
            .disabled(true)
            .matchedGeometryEffect(id: "map", in: namespace)
            
            // Invisible tap area
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        showFullScreen = true
                    }
                }
        }
        .onChange(of: country) { oldValue, newValue in
            // Update map region when country changes
            withAnimation(.easeInOut(duration: 0.5)) {
                switch newValue {
                case .unitedStates:
                    mapRegion = MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: 40.8283, longitude: -106.5795),
                        span: MKCoordinateSpan(latitudeDelta: 50, longitudeDelta: 50)
                    )
                case .canada:
                    mapRegion = MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: 56.1304, longitude: -106.3468),
                        span: MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 60)
                    )
                case .mexico:
                    mapRegion = MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: 23.6345, longitude: -102.5528),
                        span: MKCoordinateSpan(latitudeDelta: 15, longitudeDelta: 20)
                    )
                }
            }
        }
    }
    
    private func coordinateForRegion(_ region: PlateRegion) -> CLLocationCoordinate2D {
        // Approximate center coordinates for regions
        // This is a simplified approach - in production you'd want more precise coordinates
        let coordinates: [String: CLLocationCoordinate2D] = [
            // United States
            "us-al": CLLocationCoordinate2D(latitude: 32.806671, longitude: -86.791130),
            "us-ak": CLLocationCoordinate2D(latitude: 61.370716, longitude: -152.404419),
            "us-az": CLLocationCoordinate2D(latitude: 33.729759, longitude: -111.431221),
            "us-ar": CLLocationCoordinate2D(latitude: 34.969704, longitude: -92.373123),
            "us-ca": CLLocationCoordinate2D(latitude: 36.116203, longitude: -119.681564),
            "us-co": CLLocationCoordinate2D(latitude: 39.059811, longitude: -105.311104),
            "us-ct": CLLocationCoordinate2D(latitude: 41.597782, longitude: -72.755371),
            "us-de": CLLocationCoordinate2D(latitude: 39.318523, longitude: -75.507141),
            "us-fl": CLLocationCoordinate2D(latitude: 27.766279, longitude: -81.686783),
            "us-ga": CLLocationCoordinate2D(latitude: 33.040619, longitude: -83.643074),
            "us-hi": CLLocationCoordinate2D(latitude: 21.094318, longitude: -157.498337),
            "us-id": CLLocationCoordinate2D(latitude: 44.240459, longitude: -114.478828),
            "us-il": CLLocationCoordinate2D(latitude: 40.349457, longitude: -88.986137),
            "us-in": CLLocationCoordinate2D(latitude: 39.849426, longitude: -86.258278),
            "us-ia": CLLocationCoordinate2D(latitude: 42.011539, longitude: -93.210526),
            "us-ks": CLLocationCoordinate2D(latitude: 38.526600, longitude: -96.726486),
            "us-ky": CLLocationCoordinate2D(latitude: 37.668140, longitude: -84.670067),
            "us-la": CLLocationCoordinate2D(latitude: 31.169546, longitude: -91.867805),
            "us-me": CLLocationCoordinate2D(latitude: 44.323535, longitude: -69.765261),
            "us-md": CLLocationCoordinate2D(latitude: 39.063946, longitude: -76.802101),
            "us-ma": CLLocationCoordinate2D(latitude: 42.230171, longitude: -71.530106),
            "us-mi": CLLocationCoordinate2D(latitude: 43.326618, longitude: -84.536095),
            "us-mn": CLLocationCoordinate2D(latitude: 45.694454, longitude: -93.900192),
            "us-ms": CLLocationCoordinate2D(latitude: 32.741646, longitude: -89.678696),
            "us-mo": CLLocationCoordinate2D(latitude: 38.456085, longitude: -92.288368),
            "us-mt": CLLocationCoordinate2D(latitude: 46.921925, longitude: -110.454353),
            "us-ne": CLLocationCoordinate2D(latitude: 41.125370, longitude: -98.268082),
            "us-nv": CLLocationCoordinate2D(latitude: 38.313515, longitude: -117.055374),
            "us-nh": CLLocationCoordinate2D(latitude: 43.452492, longitude: -71.563896),
            "us-nj": CLLocationCoordinate2D(latitude: 40.298904, longitude: -74.521011),
            "us-nm": CLLocationCoordinate2D(latitude: 34.840515, longitude: -106.248482),
            "us-ny": CLLocationCoordinate2D(latitude: 42.165726, longitude: -74.948051),
            "us-nc": CLLocationCoordinate2D(latitude: 35.630066, longitude: -79.806419),
            "us-nd": CLLocationCoordinate2D(latitude: 47.528912, longitude: -99.784012),
            "us-oh": CLLocationCoordinate2D(latitude: 40.388783, longitude: -82.764915),
            "us-ok": CLLocationCoordinate2D(latitude: 35.565342, longitude: -96.928917),
            "us-or": CLLocationCoordinate2D(latitude: 44.572021, longitude: -122.070938),
            "us-pa": CLLocationCoordinate2D(latitude: 40.590752, longitude: -77.209755),
            "us-ri": CLLocationCoordinate2D(latitude: 41.680893, longitude: -71.51178),
            "us-sc": CLLocationCoordinate2D(latitude: 33.856892, longitude: -80.945007),
            "us-sd": CLLocationCoordinate2D(latitude: 44.299782, longitude: -99.438828),
            "us-tn": CLLocationCoordinate2D(latitude: 35.747845, longitude: -86.692345),
            "us-tx": CLLocationCoordinate2D(latitude: 31.054487, longitude: -97.563461),
            "us-ut": CLLocationCoordinate2D(latitude: 40.150032, longitude: -111.862434),
            "us-vt": CLLocationCoordinate2D(latitude: 44.045876, longitude: -72.710686),
            "us-va": CLLocationCoordinate2D(latitude: 37.769337, longitude: -78.169968),
            "us-wa": CLLocationCoordinate2D(latitude: 47.400902, longitude: -121.490494),
            "us-wv": CLLocationCoordinate2D(latitude: 38.491226, longitude: -80.954453),
            "us-wi": CLLocationCoordinate2D(latitude: 44.268543, longitude: -89.616508),
            "us-wy": CLLocationCoordinate2D(latitude: 42.755966, longitude: -107.302490),
            "us-dc": CLLocationCoordinate2D(latitude: 38.907192, longitude: -77.036873),
            "us-pr": CLLocationCoordinate2D(latitude: 18.220833, longitude: -66.590149),
            "us-gu": CLLocationCoordinate2D(latitude: 13.444304, longitude: 144.793731),
            "us-vi": CLLocationCoordinate2D(latitude: 18.335765, longitude: -64.896335),
            "us-as": CLLocationCoordinate2D(latitude: -14.271000, longitude: -170.132217),
            "us-mp": CLLocationCoordinate2D(latitude: 17.330830, longitude: 145.384690),
            // Canada
            "ca-ab": CLLocationCoordinate2D(latitude: 53.933271, longitude: -116.576504),
            "ca-bc": CLLocationCoordinate2D(latitude: 53.726669, longitude: -127.647621),
            "ca-mb": CLLocationCoordinate2D(latitude: 53.760861, longitude: -98.813876),
            "ca-nb": CLLocationCoordinate2D(latitude: 46.565316, longitude: -66.461916),
            "ca-nl": CLLocationCoordinate2D(latitude: 53.135509, longitude: -57.660436),
            "ca-nt": CLLocationCoordinate2D(latitude: 64.825545, longitude: -124.845733),
            "ca-ns": CLLocationCoordinate2D(latitude: 44.682006, longitude: -63.744311),
            "ca-nu": CLLocationCoordinate2D(latitude: 70.299771, longitude: -83.107577),
            "ca-on": CLLocationCoordinate2D(latitude: 50.000000, longitude: -85.000000),
            "ca-pe": CLLocationCoordinate2D(latitude: 46.510712, longitude: -63.416813),
            "ca-qc": CLLocationCoordinate2D(latitude: 52.939916, longitude: -73.549136),
            "ca-sk": CLLocationCoordinate2D(latitude: 52.939916, longitude: -106.450864),
            "ca-yt": CLLocationCoordinate2D(latitude: 64.282327, longitude: -135.000000),
            // Mexico
            "mx-ags": CLLocationCoordinate2D(latitude: 21.885256, longitude: -102.291567),
            "mx-bcn": CLLocationCoordinate2D(latitude: 30.840634, longitude: -115.283758),
            "mx-bcs": CLLocationCoordinate2D(latitude: 26.044444, longitude: -111.666072),
            "mx-cam": CLLocationCoordinate2D(latitude: 19.830125, longitude: -90.534909),
            "mx-chp": CLLocationCoordinate2D(latitude: 16.756931, longitude: -93.129235),
            "mx-chh": CLLocationCoordinate2D(latitude: 28.632996, longitude: -106.069100),
            "mx-coa": CLLocationCoordinate2D(latitude: 27.058676, longitude: -101.706829),
            "mx-col": CLLocationCoordinate2D(latitude: 19.245234, longitude: -103.724087),
            "mx-dur": CLLocationCoordinate2D(latitude: 24.027720, longitude: -104.653176),
            "mx-gua": CLLocationCoordinate2D(latitude: 21.019015, longitude: -101.257359),
            "mx-gro": CLLocationCoordinate2D(latitude: 17.573988, longitude: -99.497688),
            "mx-hid": CLLocationCoordinate2D(latitude: 20.091143, longitude: -98.762387),
            "mx-jal": CLLocationCoordinate2D(latitude: 20.659699, longitude: -103.349609),
            "mx-mex": CLLocationCoordinate2D(latitude: 19.496873, longitude: -99.723267),
            "mx-mic": CLLocationCoordinate2D(latitude: 19.566519, longitude: -101.706829),
            "mx-mor": CLLocationCoordinate2D(latitude: 18.681305, longitude: -99.101350),
            "mx-nay": CLLocationCoordinate2D(latitude: 21.751384, longitude: -105.231098),
            "mx-nle": CLLocationCoordinate2D(latitude: 25.592172, longitude: -99.996194),
            "mx-oax": CLLocationCoordinate2D(latitude: 17.073184, longitude: -96.726588),
            "mx-pue": CLLocationCoordinate2D(latitude: 19.041440, longitude: -98.206273),
            "mx-que": CLLocationCoordinate2D(latitude: 20.588793, longitude: -100.389888),
            "mx-roo": CLLocationCoordinate2D(latitude: 19.181738, longitude: -88.479137),
            "mx-slp": CLLocationCoordinate2D(latitude: 22.156469, longitude: -100.985540),
            "mx-sin": CLLocationCoordinate2D(latitude: 25.172109, longitude: -107.801228),
            "mx-son": CLLocationCoordinate2D(latitude: 29.297019, longitude: -110.330925),
            "mx-tab": CLLocationCoordinate2D(latitude: 18.166850, longitude: -92.618927),
            "mx-tam": CLLocationCoordinate2D(latitude: 24.266940, longitude: -98.836275),
            "mx-tla": CLLocationCoordinate2D(latitude: 19.313923, longitude: -98.240447),
            "mx-ver": CLLocationCoordinate2D(latitude: 19.173773, longitude: -96.134224),
            "mx-yuc": CLLocationCoordinate2D(latitude: 20.684285, longitude: -89.094338),
            "mx-zac": CLLocationCoordinate2D(latitude: 23.293451, longitude: -102.700737),
            "mx-cmx": CLLocationCoordinate2D(latitude: 19.432608, longitude: -99.133209)
        ]
        
        return coordinates[region.id] ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
    }
}

#Preview {
    do {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Trip.self, configurations: configuration)

        let context = container.mainContext
        let authService = FirebaseAuthService()
        let sampleTrip = Trip(name: "Autumn Road Trip")
        context.insert(sampleTrip)

        return TripTrackerView(trip: sampleTrip)
            .modelContainer(container)
            .environmentObject(authService)
    } catch {
        return Text("Preview Error: \(error.localizedDescription)")
    }
}

