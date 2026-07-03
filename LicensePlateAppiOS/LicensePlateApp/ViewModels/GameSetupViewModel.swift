//
//  GameSetupViewModel.swift
//  LicensePlateApp
//
//  Game type, play style, and country scope. Creates trip or adds games.
//

import Foundation
import Combine

@MainActor
final class GameSetupViewModel: ObservableObject {
    let context: GameSetupContext

    @Published var defaultGameMode: GameMode = .collaborative
    @Published var selectedGameTypes: Set<GameType> = [.licensePlate]
    @Published var includeUS: Bool = true
    @Published var includeCanada: Bool = true
    @Published var includeMexico: Bool = true
    @Published var includeUSTerritories: Bool = true
    @Published var includeDC: Bool = true
    @Published var includeCanadianTerritories: Bool = true

    @Published private(set) var errorMessage: String?
    @Published private(set) var isSubmitting: Bool = false
    @Published private(set) var shouldPresentTripLimitPaywall = false
    @Published private(set) var selectableGameTypes: [GameType] = GameType.availableTypes

    private let tripSessionRepository: TripSessionRepositoryProtocol
    private let gameInstanceRepository: GameInstanceRepositoryProtocol
    private let tripInviteRepository: TripInviteRepositoryProtocol
    private let lifecycleService: TripSessionLifecycleServiceProtocol
    private let gameInstanceLifecycleService: GameInstanceLifecycleServiceProtocol
    private let tripEntitlementGate: TripEntitlementGate
    private let authService: FirebaseAuthService
    private let newTripDefaultsStore: NewTripDefaultsStoring

    var primaryActionTitle: String {
        switch context {
        case .newTrip: return "Create".localized
        case .addToExistingTrip: return "Add Game".localized
        }
    }

    init(
        context: GameSetupContext,
        tripSessionRepository: TripSessionRepositoryProtocol,
        gameInstanceRepository: GameInstanceRepositoryProtocol,
        tripInviteRepository: TripInviteRepositoryProtocol = TripInviteRepository.shared,
        lifecycleService: TripSessionLifecycleServiceProtocol = TripSessionLifecycleService.shared,
        gameInstanceLifecycleService: GameInstanceLifecycleServiceProtocol = GameInstanceLifecycleService.shared,
        tripEntitlementGate: TripEntitlementGate = .shared,
        authService: FirebaseAuthService,
        newTripDefaultsStore: NewTripDefaultsStoring = UserDefaultsNewTripDefaultsStore()
    ) {
        self.context = context
        self.tripSessionRepository = tripSessionRepository
        self.gameInstanceRepository = gameInstanceRepository
        self.tripInviteRepository = tripInviteRepository
        self.lifecycleService = lifecycleService
        self.gameInstanceLifecycleService = gameInstanceLifecycleService
        self.tripEntitlementGate = tripEntitlementGate
        self.authService = authService
        self.newTripDefaultsStore = newTripDefaultsStore

        switch context {
        case .newTrip:
            applyNewTripDefaults(newTripDefaultsStore.load())
        case .addToExistingTrip:
            loadAddGameContext()
        }
    }

    func logSetupScreenAppeared() {
        switch context {
        case .newTrip:
            AnalyticsService.shared.log(.gameSetupOpened)
            AnalyticsService.shared.logScreenView(screenName: "game_setup")
        case .addToExistingTrip(let sessionId):
            AnalyticsService.shared.log(.gameSetupAddGameOpened(tripSessionId: sessionId.uuidString))
            AnalyticsService.shared.logScreenView(screenName: "game_setup_add_game")
        }
    }

    var enabledCountries: [PlateRegion.Country] {
        var list: [PlateRegion.Country] = []
        if includeUS { list.append(.unitedStates) }
        if includeCanada { list.append(.canada) }
        if includeMexico { list.append(.mexico) }
        return list
    }

    var canConfirm: Bool {
        !selectedGameTypes.isEmpty
            && selectedGameTypes.contains(where: { $0.isAvailable && selectableGameTypes.contains($0) })
            && !enabledCountries.isEmpty
    }

    var countryValidationMessage: String? {
        enabledCountries.isEmpty ? "Select at least one country.".localized : nil
    }

    var currentGameScopeOptions: GameDefaultScopeOptions {
        GameDefaultScopeOptions(
            includeUS: includeUS,
            includeCanada: includeCanada,
            includeMexico: includeMexico,
            includeUSTerritories: includeUSTerritories,
            includeDC: includeDC,
            includeCanadianTerritories: includeCanadianTerritories
        )
    }

    /// True when Game Options country/territory toggles match Settings → Game Defaults.
    var usesGameDefaultOptions: Bool {
        currentGameScopeOptions == newTripDefaultsStore.load().gameDefaultScopeOptions
    }

    func applyTerritoryGatingFromCountryToggles() {
        if !includeUS {
            includeUSTerritories = false
            includeDC = false
        }
        if !includeCanada {
            includeCanadianTerritories = false
        }
    }

    func toggleGameType(_ gameType: GameType) {
        guard selectableGameTypes.contains(gameType) else { return }
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

    func setError(_ message: String) {
        errorMessage = message
    }

    func createTrip() throws -> TripSession {
        guard case .newTrip(let draft) = context else {
            throw CombinedTripSetupError.couldNotAddGame
        }

        errorMessage = nil
        shouldPresentTripLimitPaywall = false
        isSubmitting = true
        defer { isSubmitting = false }

        let types = Array(selectedGameTypes.filter { $0.isAvailable })
        guard !types.isEmpty else {
            throw CombinedTripSetupError.noGameTypesSelected
        }

        let createdBy = authService.currentUser?.firebaseUID ?? authService.currentUser?.id ?? "unknown"
        applyTerritoryGatingFromCountryToggles()

        let request = TripSessionCreationRequest(
            tripName: draft.tripName,
            gameTypes: types,
            defaultGameMode: defaultGameMode,
            countryList: enabledCountries,
            territoryOptions: LicensePlateTerritoryOptions(
                includeUSTerritories: includeUSTerritories,
                includeCanadianTerritories: includeCanadianTerritories,
                includeDC: includeDC
            ),
            startTripRightAway: draft.startTripRightAway,
            tripSource: "trip_setup",
            createdBy: createdBy
        )

        do {
            let result = try TripSessionFactory.create(
                request: request,
                tripSessionRepository: tripSessionRepository,
                gameInstanceRepository: gameInstanceRepository,
                lifecycleService: lifecycleService,
                tripEntitlementGate: tripEntitlementGate,
                user: authService.currentUser
            )
            return result.session
        } catch let error as TripEntitlementGateError {
            shouldPresentTripLimitPaywall = true
            throw error
        }
    }

    @discardableResult
    func addGame() throws -> GameInstance {
        guard case .addToExistingTrip(let sessionId) = context else {
            throw CombinedTripSetupError.couldNotAddGame
        }

        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }

        guard let session = try tripSessionRepository.session(byId: sessionId) else {
            throw CombinedTripSetupError.sessionNotFound
        }
        guard isTripCreator(for: session) else {
            throw CombinedTripSetupError.notTripCreator
        }
        if session.status == .ended || session.status == .cancelled {
            throw CombinedTripSetupError.tripTerminal
        }

        let countryList = enabledCountries
        guard !countryList.isEmpty else {
            throw CombinedTripSetupError.noCountriesSelected
        }

        applyTerritoryGatingFromCountryToggles()

        let games = try gameInstanceRepository.fetchByTripSession(sessionId: sessionId)
        let types = Array(selectedGameTypes.filter { $0.isAvailable && selectableGameTypes.contains($0) })
        guard !types.isEmpty else {
            throw CombinedTripSetupError.noGameTypesSelected
        }

        for type in types {
            try GameplayLifecycleRules.validateCanAddGame(ofType: type.rawValue, existingGames: games)
        }

        let template = games.first { $0.definitionId == GameType.licensePlate.rawValue }
        let lpConfig = CombinedGameAssembler.licensePlateConfig(
            from: countryList,
            territoryOptions: LicensePlateTerritoryOptions(
                includeUSTerritories: includeUSTerritories,
                includeCanadianTerritories: includeCanadianTerritories,
                includeDC: includeDC
            )
        )

        var choicesByGameType: [GameType: GameSetupChoice] = [:]
        for type in types {
            let existing = games.first { $0.definitionId == type.rawValue }
            choicesByGameType[type] = GameSetupChoice(
                gameType: type,
                gameMode: defaultGameMode,
                teams: existing?.teams ?? template?.teams ?? []
            )
        }

        let config = CombinedGameConfiguration(enabledGameTypes: types)
        let assembled = CombinedGameAssembler.assemble(
            session: session,
            config: config,
            choicesByGameType: choicesByGameType,
            licensePlateConfig: lpConfig
        )
        guard let instance = assembled.first else {
            throw CombinedTripSetupError.couldNotAddGame
        }

        try gameInstanceRepository.create(instance: instance)

        let order = games.count + 1
        AnalyticsService.shared.log(.gameInstanceCreated(
            gameInstanceId: instance.id.uuidString,
            gameType: instance.definitionId,
            gameMode: instance.commonConfig.gameMode.rawValue,
            tripId: sessionId.uuidString,
            gameOrderInTrip: order
        ))

        if session.status == .active, session.startedAt != nil {
            do {
                try gameInstanceLifecycleService.startGame(sessionId: sessionId, gameInstanceId: instance.id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        Task { @MainActor in
            try? await TripCanonicalRemoteSyncService.shared.publishFullSession(sessionId: sessionId)
        }

        return instance
    }

    func publishCanonicalToRemote(session: TripSession) async {
        do {
            try await TripCanonicalRemoteSyncService.shared.publishFullSession(sessionId: session.id)
        } catch {
            #if DEBUG
            print("GameSetupViewModel: publishCanonicalToRemote failed: \(error)")
            #endif
        }
    }

    func sendSetupInvites(for session: TripSession) async {
        guard case .newTrip(let draft) = context else { return }
        guard !draft.selectedPassengerIds.isEmpty else { return }
        guard let fromUserId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id else { return }

        for toUserId in draft.selectedPassengerIds {
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

    private func loadAddGameContext() {
        guard case .addToExistingTrip(let sessionId) = context else { return }

        let games = (try? gameInstanceRepository.fetchByTripSession(sessionId: sessionId)) ?? []
        selectableGameTypes = GameType.availableTypes.filter { type in
            (try? GameplayLifecycleRules.validateCanAddGame(ofType: type.rawValue, existingGames: games)) != nil
        }
        selectedGameTypes = Set(selectableGameTypes.prefix(1))

        if let config = games.first(where: { $0.definitionId == GameType.licensePlate.rawValue })?.licensePlateConfig() {
            applyLicensePlateConfig(config)
            defaultGameMode = games.first(where: { $0.definitionId == GameType.licensePlate.rawValue })?.commonConfig.gameMode ?? .collaborative
        } else {
            applyNewTripDefaults(UserDefaultsNewTripDefaultsStore().load())
        }
    }

    private func applyLicensePlateConfig(_ config: LicensePlateGameConfig) {
        let countries = Set(config.selectedCountries)
        includeUS = countries.contains(.unitedStates)
        includeCanada = countries.contains(.canada)
        includeMexico = countries.contains(.mexico)
        includeUSTerritories = config.territoryOptions.includeUSTerritories
        includeDC = config.territoryOptions.includeDC
        includeCanadianTerritories = config.territoryOptions.includeCanadianTerritories
    }

    private func applyNewTripDefaults(_ defaults: NewTripDefaults) {
        let scope = defaults.gameDefaultScopeOptions
        includeUS = scope.includeUS
        includeCanada = scope.includeCanada
        includeMexico = scope.includeMexico
        includeUSTerritories = scope.includeUSTerritories
        includeDC = scope.includeDC
        includeCanadianTerritories = scope.includeCanadianTerritories
    }

    private func isTripCreator(for session: TripSession) -> Bool {
        let uid = authService.currentUser?.firebaseUID ?? authService.currentUser?.id
        guard let uid, let createdBy = session.createdBy else { return false }
        return createdBy == uid
    }
}
