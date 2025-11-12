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
    @Bindable var trip: Trip
    @StateObject private var speechRecognizer = SpeechRecognizer()

    @State private var selectedTab: Tab = .list
    @State private var lastMatchedRegion: PlateRegion?
    @State private var showMatchConfirmation = false
    @State private var lastProcessedText: String = ""
    @State private var showSettings = false
    @AppStorage("skipVoiceConfirmation") private var skipVoiceConfirmation = false

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
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(Color.Theme.primaryBlue)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
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
            if showMatchConfirmation, let region = lastMatchedRegion {
                VoiceConfirmationDialog(
                    region: region,
                    onAdd: {
                        confirmAddRegion(region)
                    },
                    onCancel: {
                        showMatchConfirmation = false
                        lastMatchedRegion = nil
                    },
                    skipConfirmation: $skipVoiceConfirmation
                )
            }
        }
    }

    private var header: some View {
        VStack(spacing: 16) {
            Text(trip.name)
                .font(.system(.title2, design: .rounded))
                .fontWeight(.bold)
                .foregroundStyle(Color.Theme.primaryBlue)

            HStack(spacing: 24) {
                summaryChip(title: "Found", value: "\(trip.foundRegionIDs.count)")
                summaryChip(title: "Remaining", value: "\(PlateRegion.all.count - trip.foundRegionIDs.count)")
            }
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.Theme.cardBackground)
                .padding(.horizontal, 24)
        )
        .padding(.top, 20)
        .padding(.bottom, 16)
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
        //ScrollView {
        //  LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
      List {
        ForEach(PlateRegion.groupedByCountry(), id: \.country) { group in
              Section() {
                ForEach(group.regions) { region in
                  RegionCellView(
                    region: region,
                    isSelected: trip.hasFound(regionID: region.id),
                    toggleAction: { toggle(regionID: region.id) }
                  )
                  .listRowBackground(Color.Theme.cardBackground)
                }
              } header : {
                Text(group.country.rawValue)
                  .font(.headline)
                  .foregroundColor(Color.Theme.primaryBlue)
                  .frame(maxWidth: .infinity, alignment: .leading) // Expands to fill available width
                  .padding() // Adds padding around the text
                  .background(Color.Theme.background) // Sets the background color
                  .listRowInsets(EdgeInsets()) // Removes default insets
              }
            }
          }
        //}
      .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(Color.Theme.background)
    }

    private func toggle(regionID: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            trip.toggle(regionID: regionID)
        }

        do {
            try modelContext.save()
        } catch {
            assertionFailure("Failed to save trip update: \(error)")
        }
    }

    private var voiceCaptureView: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Microphone button - push and hold
            ZStack {
                Circle()
                    .fill(speechRecognizer.isListening ? Color.Theme.primaryBlue : Color.Theme.cardBackground)
                    .frame(width: 120, height: 120)
                    .shadow(color: Color.black.opacity(0.15), radius: 15, x: 0, y: 8)
                
                if speechRecognizer.isListening {
                    Circle()
                        .stroke(Color.Theme.accentYellow, lineWidth: 4)
                        .frame(width: 140, height: 140)
                        .opacity(0.6)
                        .scaleEffect(speechRecognizer.isListening ? 1.1 : 1.0)
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: speechRecognizer.isListening)
                }
                
                Image(systemName: speechRecognizer.isListening ? "mic.fill" : "mic.slash.fill")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(speechRecognizer.isListening ? Color.white : Color.Theme.primaryBlue)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !speechRecognizer.isListening && speechRecognizer.authorizationStatus == .authorized {
                            playStartSound()
                            speechRecognizer.startListening()
                        }
                    }
                    .onEnded { _ in
                        if speechRecognizer.isListening {
                            speechRecognizer.stopListening()
                        }
                    }
            )
            .disabled(speechRecognizer.authorizationStatus != .authorized)
            
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
                        .frame(maxHeight: 80)
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
        .padding(.top, 40)
        .background(Color.Theme.background)
        .task {
            await requestSpeechAuthorizationIfNeeded()
        }
    }
    
    private func playStartSound() {
        // Play system sound to indicate recording has started
        AudioServicesPlaySystemSound(1057) // System sound for recording start
    }
    
    private func requestSpeechAuthorizationIfNeeded() async {
        if speechRecognizer.authorizationStatus == .notDetermined {
            await speechRecognizer.requestAuthorization()
        }
    }
    
    private func processRecognizedText(_ text: String) {
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
        
        for region in PlateRegion.all {
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
            if skipVoiceConfirmation {
                // Auto-add without confirmation
                confirmAddRegion(region)
            } else {
                // Show confirmation popup
                showMatchConfirmation = true
            }
        } else {
            print("ℹ️ [Speech Match] Region \(region.name) already found, skipping")
        }
    }
    
    private func confirmAddRegion(_ region: PlateRegion) {
        toggle(regionID: region.id) // this toggles instead of a discrete set...we probably should have a direct set, just incase this gets called where it shouldn't (right now we make sure the trip hasn't found it)
        showMatchConfirmation = false
        lastMatchedRegion = nil
        
        // Clear recognized text and reset processed text after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            speechRecognizer.recognizedText = ""
            lastProcessedText = ""
        }
    }

    private var customTabBar: some View {
        HStack(spacing: 16) {
            ForEach(Tab.allCases) { tab in
                Button {
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
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.Theme.cardBackground)
                .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: -3)
                .padding(.horizontal, 12)
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
    .padding(.top, 60)
  }

}

private struct RegionCellView: View {
    let region: PlateRegion
    let isSelected: Bool
    var toggleAction: () -> Void

    var body: some View {
        Button {
            toggleAction()
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
                    Text("Hey, we heard the following \(region.country == .unitedStates ? "state" : region.country == .canada ? "province" : "state"):")
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

// Settings View
private struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("skipVoiceConfirmation") private var skipVoiceConfirmation = false
    @AppStorage("holdToTalk") private var holdToTalk = true
    
    enum SettingsSection: String, CaseIterable {
        case voice = "Voice"
        
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
                            switch section {
                            case .voice:
                                voiceSettings
                            }
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
    
    private var voiceSettings: some View {
        Group {
            SettingToggleRow(
                title: "Skip Confirmation",
                description: "Automatically add plates without confirmation",
                isOn: $skipVoiceConfirmation
            )
            
            SettingToggleRow(
                title: "Hold to Talk",
                description: "Press and hold the microphone button to record",
                isOn: $holdToTalk
            )
        }
    }
}

// Reusable setting toggle row with card styling
private struct SettingToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                
                Text(description)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .tint(Color.Theme.primaryBlue)
                .labelsHidden()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.Theme.cardBackground)
        )
        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
    }
}

#Preview {
    do {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Trip.self, configurations: configuration)

        let context = container.mainContext
        let sampleTrip = Trip(name: "Autumn Road Trip")
        context.insert(sampleTrip)

        return TripTrackerView(trip: sampleTrip)
            .modelContainer(container)
    } catch {
        return Text("Preview Error: \(error.localizedDescription)")
    }
}

