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
    @Published var selectedPassengerIds: Set<String> = []

    @Published private(set) var errorMessage: String?
    @Published private(set) var isCreating: Bool = false
    @Published private(set) var shouldPresentTripLimitPaywall = false

    // MARK: - Dependencies

    private let tripSessionRepository: TripSessionRepositoryProtocol
    private let gameInstanceRepository: GameInstanceRepositoryProtocol
    private let tripInviteRepository: TripInviteRepositoryProtocol
    private let lifecycleService: TripSessionLifecycleServiceProtocol
    private let tripEntitlementGate: TripEntitlementGate
    private let authService: FirebaseAuthService

    init(
        tripSessionRepository: TripSessionRepositoryProtocol,
        gameInstanceRepository: GameInstanceRepositoryProtocol,
        tripInviteRepository: TripInviteRepositoryProtocol = TripInviteRepository.shared,
        lifecycleService: TripSessionLifecycleServiceProtocol = TripSessionLifecycleService.shared,
        tripEntitlementGate: TripEntitlementGate = .shared,
        authService: FirebaseAuthService
    ) {
        self.tripSessionRepository = tripSessionRepository
        self.gameInstanceRepository = gameInstanceRepository
        self.tripInviteRepository = tripInviteRepository
        self.lifecycleService = lifecycleService
        self.tripEntitlementGate = tripEntitlementGate
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

    func dismissTripLimitPaywall() {
        shouldPresentTripLimitPaywall = false
    }

    /// Call from the View when createTrip throws so the error alert can display the message.
    func setError(_ message: String) {
        errorMessage = message
    }

    /// Creates TripSession (status `.created`, `startedAt` nil) and GameInstances. When `startTripRightAway`, calls `startTrip` so the session becomes `.active`, games start, and trip/game events are appended. Returns the session as persisted (reloaded) on success.
    func createTrip() throws -> TripSession {
        errorMessage = nil
        shouldPresentTripLimitPaywall = false
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

        let createdBy = authService.currentUser?.firebaseUID ?? authService.currentUser?.id ?? "unknown"
        do {
            try tripEntitlementGate.validateCanAddActiveTrip(
                user: authService.currentUser,
                userId: createdBy,
                source: .create
            )
        } catch let error as TripEntitlementGateError {
            shouldPresentTripLimitPaywall = true
            throw error
        }

        applyTerritoryGatingFromCountryToggles()

        let createdAt = Date()
        let finalName = tripName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Self.defaultTripName(from: createdAt)
            : tripName.trimmingCharacters(in: .whitespacesAndNewlines)

        let sessionId = UUID()
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
        //TODO need to not haradcode this and inform when unselecting we need atleast 1 game?
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

    /// Publishes session + games to Firestore so invitees can bootstrap. Best effort.
    func publishCanonicalToRemote(session: TripSession) async {
        do {
            try await TripCanonicalRemoteSyncService.shared.publishFullSession(sessionId: session.id)
        } catch {
            #if DEBUG
            print("CombinedTripSetupViewModel: publishCanonicalToRemote failed: \(error)")
            #endif
        }
    }

    /// Sends invites selected during setup. This is best effort and does not block creation success.
    func sendSetupInvites(for session: TripSession) async {
        guard !selectedPassengerIds.isEmpty else { return }
        guard let fromUserId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id else { return }

        for toUserId in selectedPassengerIds {
            do {
                _ = try await tripInviteRepository.sendTripInvite(
                    tripSessionId: session.id.uuidString,
                    tripName: session.name,
                    fromUserId: fromUserId,
                    toUserId: toUserId,
                    expiresAt: nil
                )
            } catch {
                AnalyticsService.shared.log(.tripInviteSendFailed(
                    tripSessionId: session.id.uuidString,
                    error: error.localizedDescription
                ))
            }
        }
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
