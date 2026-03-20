//
//  CombinedTripSetupViewModel.swift
//  LicensePlateApp
//
//  Step 06 — ViewModel for combined trip setup: game types, countries, options. Creates TripSession + GameInstances (canonical only).
//

import Foundation
import SwiftData
import Combine

@MainActor
final class CombinedTripSetupViewModel: ObservableObject {
    // MARK: - State

    @Published var tripName: String = ""
    @Published var selectedGameTypes: Set<GameType> = [.licensePlate]
    @Published var includeUS: Bool = true
    @Published var includeCanada: Bool = true
    @Published var includeMexico: Bool = true
    @Published var includeUSTerritories: Bool = true
    @Published var includeDC: Bool = true
    @Published var includeCanadianTerritories: Bool = true
    @Published var startTripRightAway: Bool = false
    @Published var skipVoiceConfirmation: Bool = false
    @Published var holdToTalk: Bool = true
    @Published var saveLocationWhenMarkingPlates: Bool = true
    @Published var showMyLocationOnLargeMap: Bool = true
    @Published var trackMyLocationDuringTrip: Bool = true
    @Published var showMyActiveTripOnLargeMap: Bool = true
    @Published var showMyActiveTripOnSmallMap: Bool = true

    @Published private(set) var errorMessage: String?
    @Published private(set) var isCreating: Bool = false

    // MARK: - Dependencies

    private let tripSessionRepository: TripSessionRepositoryProtocol
    private let gameInstanceRepository: GameInstanceRepositoryProtocol
    private let lifecycleService: TripSessionLifecycleServiceProtocol
    private let authService: FirebaseAuthService

    init(
        tripSessionRepository: TripSessionRepositoryProtocol,
        gameInstanceRepository: GameInstanceRepositoryProtocol,
        lifecycleService: TripSessionLifecycleServiceProtocol = TripSessionLifecycleService.shared,
        authService: FirebaseAuthService
    ) {
        self.tripSessionRepository = tripSessionRepository
        self.gameInstanceRepository = gameInstanceRepository
        self.lifecycleService = lifecycleService
        self.authService = authService
    }

    // MARK: - Validation

    var enabledCountries: [PlateRegion.Country] {
        var list: [PlateRegion.Country] = []
        if includeUS { list.append(.unitedStates) }
        if includeCanada { list.append(.canada) }
        if includeMexico { list.append(.mexico) }
        return list
    }

    var canCreate: Bool {
        !selectedGameTypes.isEmpty
            && selectedGameTypes.contains(where: { $0.isAvailable })
            && !enabledCountries.isEmpty
    }

    var countryValidationMessage: String? {
        enabledCountries.isEmpty ? "Select at least one country.".localized : nil
    }

    /// Clears territory toggles when their parent country is off (UI convenience; assembler normalizes on save too).
    func applyTerritoryGatingFromCountryToggles() {
        if !includeUS {
            includeUSTerritories = false
            includeDC = false
        }
        if !includeCanada {
            includeCanadianTerritories = false
        }
    }

    // MARK: - Actions

    func toggleGameType(_ gameType: GameType) {
        if selectedGameTypes.contains(gameType) {
            selectedGameTypes.remove(gameType)
        } else {
            selectedGameTypes.insert(gameType)
        }
    }

    func clearError() {
        errorMessage = nil
    }

    /// Call from the View when createTrip throws so the error alert can display the message.
    func setError(_ message: String) {
        errorMessage = message
    }

    /// Creates TripSession and GameInstances only (canonical model). Appends trip_started/game_started events when startTripRightAway. Returns the created TripSession on success.
    /// Solo is the one-participant case: one TripSession, one TripParticipant (creator), and one default GameInstance when a single game type is selected. No legacy Trip; no dual-write.
    func createTrip(modelContext: ModelContext) throws -> TripSession {
        errorMessage = nil
        isCreating = true
        defer { isCreating = false }

        let countryList = enabledCountries
        guard !countryList.isEmpty else {
            throw CombinedTripSetupError.noCountriesSelected
        }
        let types = selectedGameTypes.filter { $0.isAvailable }
        guard !types.isEmpty else {
            throw CombinedTripSetupError.noGameTypesSelected
        }

        applyTerritoryGatingFromCountryToggles()

        let createdAt = Date()
        let finalName = tripName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Self.defaultTripName(from: createdAt)
            : tripName.trimmingCharacters(in: .whitespacesAndNewlines)

        let sessionId = UUID()
        let createdBy = authService.currentUser?.firebaseUID ?? authService.currentUser?.id ?? "unknown"
        let participant = TripParticipant(userId: createdBy, role: .owner, joinedAt: createdAt)
        let mode: TripMode = .solo
        let startedAt = startTripRightAway ? createdAt : nil

        let session = TripSession(
            id: sessionId,
            name: finalName,
            status: .active,
            mode: mode,
            createdAt: createdAt,
            createdBy: createdBy,
            startedAt: startedAt,
            endedAt: nil,
            endedBy: nil,
            participants: [participant]
        )

        try tripSessionRepository.create(session: session)

        let config = CombinedGameConfiguration(enabledGameTypes: Array(types))
        let territoryOpts = LicensePlateTerritoryOptions(
            includeUSTerritories: includeUSTerritories,
            includeCanadianTerritories: includeCanadianTerritories,
            includeDC: includeDC
        )
        let lpConfig = CombinedGameAssembler.licensePlateConfig(from: countryList, territoryOptions: territoryOpts)
        let instances = CombinedGameAssembler.assemble(session: session, config: config, licensePlateConfig: lpConfig)
        
        AnalyticsService.shared.log(.tripSessionCreated(tripId: sessionId.uuidString, tripStatus: session.status.rawValue, tripParticipantCount: session.participants.count, tripActiveGameCount: instances.count, tripSource: "combined_setup"))
        for (index, instance) in instances.enumerated() {
            try gameInstanceRepository.create(instance: instance)
            AnalyticsService.shared.log(.gameInstanceCreated(gameInstanceId: instance.id.uuidString, gameType: instance.definitionId, gameMode: instance.commonConfig.gameMode.rawValue, tripId: sessionId.uuidString, gameOrderInTrip: index + 1))
        }
        AnalyticsService.shared.log(.combinedTripCreated(gameTypes: types.map(\.rawValue), tripSessionId: sessionId.uuidString, tripMode: session.mode.rawValue, participantCount: session.participants.count, gameCount: instances.count))
        if session.startedAt != nil {
            try lifecycleService.startTrip(sessionId: sessionId, actorId: createdBy)
        }
        return session
    }

    private static func defaultTripName(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

enum CombinedTripSetupError: LocalizedError {
    case noCountriesSelected
    case noGameTypesSelected

    var errorDescription: String? {
        switch self {
        case .noCountriesSelected: return "Select at least one country.".localized
        case .noGameTypesSelected: return "Select at least one game.".localized
        }
    }
}
