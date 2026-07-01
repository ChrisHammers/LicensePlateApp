//
//  TripSessionFactory.swift
//  LicensePlateApp
//
//  Shared TripSession + GameInstance creation used by combined setup and quick solo.
//

import Foundation

struct TripSessionCreationRequest {
    let tripName: String?
    let gameTypes: [GameType]
    let defaultGameMode: GameMode
    let countryList: [PlateRegion.Country]
    let territoryOptions: LicensePlateTerritoryOptions
    let startTripRightAway: Bool
    let tripSource: String
    let createdBy: String
}

struct TripSessionCreationResult {
    let session: TripSession
    let instances: [GameInstance]
}

enum TripSessionFactory {

    @MainActor
    static func create(
        request: TripSessionCreationRequest,
        tripSessionRepository: TripSessionRepositoryProtocol,
        gameInstanceRepository: GameInstanceRepositoryProtocol,
        lifecycleService: TripSessionLifecycleServiceProtocol,
        tripEntitlementGate: TripEntitlementGate,
        user: AppUser?
    ) throws -> TripSessionCreationResult {
        guard !request.countryList.isEmpty else {
            throw CombinedTripSetupError.noCountriesSelected
        }
        let types = request.gameTypes.filter(\.isAvailable)
        guard !types.isEmpty else {
            throw CombinedTripSetupError.noGameTypesSelected
        }

        do {
            try tripEntitlementGate.validateCanAddActiveTrip(
                user: user,
                userId: request.createdBy,
                source: .create
            )
        } catch {
            throw error
        }

        let createdAt = Date()
        let finalName = request.tripName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? request.tripName!.trimmingCharacters(in: .whitespacesAndNewlines)
            : defaultTripName(from: createdAt)

        let sessionId = UUID()
        let participant = TripParticipant(userId: request.createdBy, role: .owner, joinedAt: createdAt)

        let session = TripSession(
            id: sessionId,
            name: finalName,
            status: .created,
            createdAt: createdAt,
            createdBy: request.createdBy,
            startedAt: nil,
            endedAt: nil,
            endedBy: nil,
            participants: [participant]
        )

        try tripSessionRepository.create(session: session)

        let config = CombinedGameConfiguration(enabledGameTypes: types)
        var choicesByGameType: [GameType: GameSetupChoice] = [:]
        for type in types {
            choicesByGameType[type] = GameSetupChoice(gameType: type, gameMode: request.defaultGameMode, teams: [])
        }
        let lpConfig = CombinedGameAssembler.licensePlateConfig(
            from: request.countryList,
            territoryOptions: request.territoryOptions
        )
        let instances = CombinedGameAssembler.assemble(
            session: session,
            config: config,
            choicesByGameType: choicesByGameType,
            licensePlateConfig: lpConfig
        )

        let gameModeStrings = instances.map(\.commonConfig.gameMode.rawValue)
        let hasTeams = instances.contains { !$0.teams.isEmpty }

        AnalyticsService.shared.log(.tripSessionCreated(
            tripId: sessionId.uuidString,
            tripStatus: session.status.rawValue,
            tripParticipantCount: session.participants.count,
            tripActiveGameCount: instances.count,
            tripSource: request.tripSource
        ))
        for (index, instance) in instances.enumerated() {
            try gameInstanceRepository.create(instance: instance)
            AnalyticsService.shared.log(.gameInstanceCreated(
                gameInstanceId: instance.id.uuidString,
                gameType: instance.definitionId,
                gameMode: instance.commonConfig.gameMode.rawValue,
                tripId: sessionId.uuidString,
                gameOrderInTrip: index + 1
            ))
        }
        AnalyticsService.shared.log(.combinedTripCreated(
            gameTypes: types.map(\.rawValue),
            tripSessionId: sessionId.uuidString,
            participantCount: session.participants.count,
            gameCount: instances.count,
            gameModes: gameModeStrings,
            hasTeams: hasTeams
        ))

        if request.startTripRightAway {
            try lifecycleService.startTrip(sessionId: sessionId, actorId: request.createdBy)
        }

        let persisted = try tripSessionRepository.session(byId: sessionId) ?? session
        return TripSessionCreationResult(session: persisted, instances: instances)
    }

    private static func defaultTripName(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
