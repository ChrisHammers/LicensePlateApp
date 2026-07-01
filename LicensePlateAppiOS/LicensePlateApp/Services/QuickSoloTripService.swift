//
//  QuickSoloTripService.swift
//  LicensePlateApp
//
//  Programmatic solo trip creation for first-session quick path.
//

import Foundation

@MainActor
final class QuickSoloTripService {
    static let shared = QuickSoloTripService()

    private let tripSessionRepository: TripSessionRepositoryProtocol
    private let gameInstanceRepository: GameInstanceRepositoryProtocol
    private let lifecycleService: TripSessionLifecycleServiceProtocol
    private let tripEntitlementGate: TripEntitlementGate
    private let newTripDefaultsStore: NewTripDefaultsStoring

    init(
        tripSessionRepository: TripSessionRepositoryProtocol = TripSessionRepository.shared,
        gameInstanceRepository: GameInstanceRepositoryProtocol = GameInstanceRepository.shared,
        lifecycleService: TripSessionLifecycleServiceProtocol = TripSessionLifecycleService.shared,
        tripEntitlementGate: TripEntitlementGate = .shared,
        newTripDefaultsStore: NewTripDefaultsStoring = UserDefaultsNewTripDefaultsStore()
    ) {
        self.tripSessionRepository = tripSessionRepository
        self.gameInstanceRepository = gameInstanceRepository
        self.lifecycleService = lifecycleService
        self.tripEntitlementGate = tripEntitlementGate
        self.newTripDefaultsStore = newTripDefaultsStore
    }

    /// Creates a started solo license-plate trip using new-trip defaults. Offline-safe (local SwiftData).
    func createAndStartQuickSoloTrip(authService: FirebaseAuthService) throws -> QuickSoloLaunchIntent {
        let defaults = newTripDefaultsStore.load()
        let createdBy = authService.currentUser?.firebaseUID ?? authService.currentUser?.id ?? "unknown"

        var countryList: [PlateRegion.Country] = []
        if defaults.includeUS { countryList.append(.unitedStates) }
        if defaults.includeCanada { countryList.append(.canada) }
        if defaults.includeMexico { countryList.append(.mexico) }
        if countryList.isEmpty {
            countryList = [.unitedStates, .canada, .mexico]
        }

        let request = TripSessionCreationRequest(
            tripName: nil,
            gameTypes: [.licensePlate],
            defaultGameMode: .collaborative,
            countryList: countryList,
            territoryOptions: LicensePlateTerritoryOptions(
                includeUSTerritories: true,
                includeCanadianTerritories: defaults.includeCanada,
                includeDC: defaults.includeUS
            ),
            startTripRightAway: true,
            tripSource: "quick_solo",
            createdBy: createdBy
        )

        let result = try TripSessionFactory.create(
            request: request,
            tripSessionRepository: tripSessionRepository,
            gameInstanceRepository: gameInstanceRepository,
            lifecycleService: lifecycleService,
            tripEntitlementGate: tripEntitlementGate,
            user: authService.currentUser
        )

        guard let licensePlateGame = result.instances.first(where: { $0.definitionId == GameType.licensePlate.rawValue }) else {
            throw CombinedTripSetupError.noGameTypesSelected
        }

        return QuickSoloLaunchIntent(sessionId: result.session.id, gameId: licensePlateGame.id)
    }

    /// Best-effort Firestore publish after quick solo creation.
    func publishCanonicalToRemote(sessionId: UUID) async {
        do {
            try await TripCanonicalRemoteSyncService.shared.publishFullSession(sessionId: sessionId)
        } catch {
            #if DEBUG
            print("QuickSoloTripService: publishCanonicalToRemote failed: \(error)")
            #endif
        }
    }
}
