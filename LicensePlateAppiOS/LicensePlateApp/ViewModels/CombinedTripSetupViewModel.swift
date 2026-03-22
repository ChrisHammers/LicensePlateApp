//
//  CombinedTripSetupViewModel.swift
//  LicensePlateApp
//
//  Step 06 — ViewModel for combined trip setup: game types, countries, options. Creates TripSession + GameInstances (canonical only).
//  Step 6.9.4 — Default game mode from setup; game assembly uses GameSetupChoice.
//  Step 6.10 — Trip participation (solo/multiplayer) is derived from participant count, not chosen here.
//

import Foundation
import Combine

@MainActor
final class CombinedTripSetupViewModel: ObservableObject {
    // MARK: - State

    @Published var tripName: String = ""
    /// MVP: one play style for every selected game type; future UI can supply per-type choices without changing `TripSession`.
    @Published var defaultGameMode: GameMode = .collaborative
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

    // MARK: - Analytics (setup screen)

    func logSetupScreenAppeared() {
        AnalyticsService.shared.log(.combinedTripSetupOpened)
        AnalyticsService.shared.logScreenView(screenName: "combined_trip_setup")
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

    /// Creates TripSession (status `.created`, `startedAt` nil) and GameInstances. When `startTripRightAway`, calls `startTrip` so the session becomes `.active`, games start, and trip/game events are appended. Returns the session as persisted (reloaded) on success.
    func createTrip() throws -> TripSession {
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

        let session = TripSession(
            id: sessionId,
            name: finalName,
            status: .created,
            createdAt: createdAt,
            createdBy: createdBy,
            startedAt: nil,
            endedAt: nil,
            endedBy: nil,
            participants: [participant]
        )

        try tripSessionRepository.create(session: session)

        let config = CombinedGameConfiguration(enabledGameTypes: Array(types))
        var choicesByGameType: [GameType: GameSetupChoice] = [:]
        for type in types {
            choicesByGameType[type] = GameSetupChoice(gameType: type, gameMode: defaultGameMode, teams: [])
        }
        let territoryOpts = LicensePlateTerritoryOptions(
            includeUSTerritories: includeUSTerritories,
            includeCanadianTerritories: includeCanadianTerritories,
            includeDC: includeDC
        )
        let lpConfig = CombinedGameAssembler.licensePlateConfig(from: countryList, territoryOptions: territoryOpts)
        let instances = CombinedGameAssembler.assemble(
            session: session,
            config: config,
            choicesByGameType: choicesByGameType,
            licensePlateConfig: lpConfig
        )

        let gameModeStrings = instances.map(\.commonConfig.gameMode.rawValue)
        let hasTeams = instances.contains { !$0.teams.isEmpty }

        AnalyticsService.shared.log(.tripSessionCreated(tripId: sessionId.uuidString, tripStatus: session.status.rawValue, tripParticipantCount: session.participants.count, tripActiveGameCount: instances.count, tripSource: "combined_setup"))
        for (index, instance) in instances.enumerated() {
            try gameInstanceRepository.create(instance: instance)
            AnalyticsService.shared.log(.gameInstanceCreated(gameInstanceId: instance.id.uuidString, gameType: instance.definitionId, gameMode: instance.commonConfig.gameMode.rawValue, tripId: sessionId.uuidString, gameOrderInTrip: index + 1))
        }
        AnalyticsService.shared.log(.combinedTripCreated(
            gameTypes: types.map(\.rawValue),
            tripSessionId: sessionId.uuidString,
            participantCount: session.participants.count,
            gameCount: instances.count,
            gameModes: gameModeStrings,
            hasTeams: hasTeams
        ))
        if startTripRightAway {
            try lifecycleService.startTrip(sessionId: sessionId, actorId: createdBy)
        }
        return try tripSessionRepository.session(byId: sessionId) ?? session
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
