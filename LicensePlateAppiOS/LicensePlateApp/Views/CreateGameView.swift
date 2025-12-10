//
//  CreateGameView.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import SwiftUI
import SwiftData

struct CreateGameView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authService: FirebaseAuthService
    
    @State private var gameName: String = ""
    @State private var selectedGameMode: Game.GameMode = .competitive
    @State private var selectedScoringType: Game.ScoringType = .totalFound
    @State private var minTeamSize: Int = 2
    @State private var maxTeamSize: Int? = nil
    @State private var hasMaxTeamSize: Bool = false
    @State private var isPublic: Bool = false
    @State private var enabledCountries: [PlateRegion.Country] = [.unitedStates, .canada, .mexico]
    
    var currentUser: AppUser? {
        authService.currentUser
    }
    
    var body: some View {
        NavigationStack {
            AppBackgroundView {
                Form {
                    Section("Game Details".localized) {
                        TextField("Game Name".localized, text: $gameName)
                    }
                    .textCase(nil)
                    
                    Section("Game Mode".localized) {
                        Picker("Mode".localized, selection: $selectedGameMode) {
                            ForEach(Game.GameMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        
                        Text(gameModeDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .textCase(nil)
                    
                    Section("Scoring".localized) {
                        Picker("Scoring Type".localized, selection: $selectedScoringType) {
                            ForEach(Game.ScoringType.allCases, id: \.self) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                        
                        Text(scoringTypeDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .textCase(nil)
                    
                    Section("Team Settings".localized) {
                        Stepper("Minimum Team Size: \(minTeamSize)".localized, value: $minTeamSize, in: 2...10)
                        
                        Toggle("Maximum Team Size".localized, isOn: $hasMaxTeamSize)
                        
                        if hasMaxTeamSize {
                            Stepper("Maximum: \(maxTeamSize ?? 4)".localized, value: Binding(
                                get: { maxTeamSize ?? 4 },
                                set: { maxTeamSize = $0 }
                            ), in: minTeamSize...20)
                        }
                    }
                    .textCase(nil)
                    
                    Section("Countries".localized) {
                        ForEach(PlateRegion.Country.allCases) { country in
                            Toggle(country.rawValue, isOn: Binding(
                                get: { enabledCountries.contains(country) },
                                set: { isOn in
                                    if isOn {
                                        enabledCountries.append(country)
                                    } else {
                                        enabledCountries.removeAll { $0 == country }
                                    }
                                }
                            ))
                        }
                    }
                    .textCase(nil)
                    
                    Section("Sharing".localized) {
                        Toggle("Public Game".localized, isOn: $isPublic)
                        
                        if isPublic {
                            Text("Anyone with the share code can join this game.".localized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .textCase(nil)
                }
                .scrollContentBackground(.hidden)
                .navigationTitle("Create Game".localized)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            Text("Cancel".localized)
                        }
                    }
                    
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            createGame()
                        } label: {
                            Text("Create".localized)
                        }
                        .disabled(gameName.isEmpty)
                    }
                }
            }
        }
    }
    
    private var gameModeDescription: String {
        switch selectedGameMode {
        case .competitive:
            return "Teams compete against each other".localized
        case .collaborative:
            return "Single team works together".localized
        }
    }
    
    private var scoringTypeDescription: String {
        switch selectedScoringType {
        case .totalFound:
            return "Highest total number of plates found wins".localized
        case .uniqueFound:
            return "Most unique plates (no duplicates) wins".localized
        case .timeBased:
            return "First team to find X plates wins".localized
        case .custom:
            return "Custom scoring rules".localized
        }
    }
    
    private func createGame() {
        guard let userID = currentUser?.id else { return }
        
        let newGame = Game(
            name: gameName,
            gameMode: selectedGameMode,
            scoringType: selectedScoringType,
            createdBy: userID,
            isPublic: isPublic,
            maxTeamSize: hasMaxTeamSize ? maxTeamSize : nil,
            minTeamSize: minTeamSize,
            enabledCountries: enabledCountries
        )
        
        if isPublic {
            newGame.generateShareCodeIfNeeded()
        }
        
        modelContext.insert(newGame)
        
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Error creating game: \(error)")
        }
    }
}

