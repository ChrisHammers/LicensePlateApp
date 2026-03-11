//
//  CombinedGameAssembler.swift
//  LicensePlateApp
//
//  Step 06 — Builds game instances for a trip session from combined game configuration. No persistence; caller uses repositories.
//  Step 07.5 — commonConfig and license_plate payload from session.
//

import Foundation

/// Assembles one GameInstance per enabled game type for a given TripSession. Caller persists via GameInstanceRepository.
enum CombinedGameAssembler {
    /// Create one GameInstance per enabled (and available) game type, all linked to the given session.
    /// - Parameters:
    ///   - session: The trip session these games belong to.
    ///   - config: Which game types are enabled; only available types are used.
    /// - Returns: Domain GameInstance values; caller must persist via GameInstanceRepository.
    static func assemble(session: TripSession, config: CombinedGameConfiguration) -> [GameInstance] {
        let types = config.availableEnabledTypes
        guard !types.isEmpty else { return [] }

        let startedAt = session.startedAt ?? Date()
        let gameMode = Self.gameMode(from: session.mode)
        let commonConfig = CommonGameConfig(
            lifecycleState: .created,
            gameMode: gameMode,
            scoringProfile: "default",
            configVersion: "1",
            summaryVisibility: true,
            configLocked: false,
            configLockReason: .none
        )

        return types.map { gameType in
            var payloadType: String?
            var payloadVersion: String?
            var payloadData: Data?
            if gameType == .licensePlate {
                let lpConfig = Self.licensePlateConfig(from: session)
                payloadType = GameType.licensePlate.rawValue
                payloadVersion = "1"
                payloadData = try? JSONEncoder().encode(lpConfig)
            }

            return GameInstance(
                definitionId: gameType.rawValue,
                sessionId: session.id,
                startedAt: startedAt,
                endedAt: session.endedAt,
                ruleSet: gameType.defaultRuleSet(),
                commonConfig: commonConfig,
                gameSpecificPayloadType: payloadType,
                gameSpecificPayloadVersion: payloadVersion,
                gameSpecificPayloadData: payloadData
            )
        }
    }

    private static func gameMode(from tripMode: TripMode) -> GameMode {
        switch tripMode {
        case .competitive: return .competitive
        case .solo, .collaborative, .combined: return .collaborative
        }
    }

    private static func licensePlateConfig(from session: TripSession) -> LicensePlateGameConfig {
        let scope = regionScope(from: session.enabledCountries)
        let territoryOptions = LicensePlateTerritoryOptions(
            includeUSTerritories: false,
            includeCanadianTerritories: true,
            includeDC: true
        )
        return LicensePlateGameConfig(regionScope: scope, territoryOptions: territoryOptions)
    }

    private static func regionScope(from countries: [PlateRegion.Country]) -> RegionScope {
        let set = Set(countries)
        if set == [.unitedStates] { return .usOnly }
        if set == [.canada] { return .canadaOnly }
        if set == [.mexico] { return .mexicoOnly }
        return .northAmerica
    }
}
