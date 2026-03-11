//
//  CombinedTripSetupViewModel.swift
//  LicensePlateApp
//
//  Step 06 — ViewModel for combined trip setup: game types, countries, options. Creates TripSession + GameInstances + legacy Trip.
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
    private let authService: FirebaseAuthService

    init(
        tripSessionRepository: TripSessionRepositoryProtocol,
        gameInstanceRepository: GameInstanceRepositoryProtocol,
        authService: FirebaseAuthService
    ) {
        self.tripSessionRepository = tripSessionRepository
        self.gameInstanceRepository = gameInstanceRepository
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

    /// Creates TripSession, GameInstances, and a legacy Trip. Inserts Trip into the given context and saves. Returns the created Trip on success.
    func createTrip(modelContext: ModelContext) throws -> Trip {
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

        let createdAt = Date()
        let finalName = tripName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Self.defaultTripName(from: createdAt)
            : tripName.trimmingCharacters(in: .whitespacesAndNewlines)

        let sessionId = UUID()
        let createdBy = authService.currentUser?.firebaseUID ?? authService.currentUser?.id ?? "unknown"
        let participant = TripParticipant(userId: createdBy, role: .owner, joinedAt: createdAt)
        let mode: TripMode = types.count > 1 ? .combined : .solo
        let startedAt = startTripRightAway ? createdAt : nil

        let session = TripSession(
            id: sessionId,
            name: finalName,
            status: startedAt != nil ? .active : .draft,
            mode: mode,
            createdBy: createdBy,
            startedAt: startedAt,
            endedAt: nil,
            endedBy: nil,
            participants: [participant],
            teams: [],
            legacyTripId: nil,
            enabledCountryRawValues: countryList.map { $0.rawValue }
        )

        try tripSessionRepository.create(session: session)

        let config = CombinedGameConfiguration(enabledGameTypes: Array(types))
        let instances = CombinedGameAssembler.assemble(session: session, config: config)
        for instance in instances {
            try gameInstanceRepository.create(instance: instance)
        }
        if session.startedAt != nil {
            try gameInstanceRepository.transitionGamesToStarted(sessionId: sessionId)
        }

        let legacyTrip = Trip(
            id: sessionId,
            createdAt: createdAt,
            lastUpdated: createdAt,
            name: finalName,
            foundRegions: [],
            skipVoiceConfirmation: skipVoiceConfirmation,
            holdToTalk: holdToTalk,
            createdBy: createdBy,
            startedAt: startedAt,
            isTripEnded: false,
            saveLocationWhenMarkingPlates: saveLocationWhenMarkingPlates,
            showMyLocationOnLargeMap: showMyLocationOnLargeMap,
            trackMyLocationDuringTrip: trackMyLocationDuringTrip,
            showMyActiveTripOnLargeMap: showMyActiveTripOnLargeMap,
            showMyActiveTripOnSmallMap: showMyActiveTripOnSmallMap,
            enabledCountries: countryList
        )
        modelContext.insert(legacyTrip)
        try modelContext.save()

        AnalyticsService.shared.log(.combinedTripCreated(gameTypes: types.map(\.rawValue)))

        return legacyTrip
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
