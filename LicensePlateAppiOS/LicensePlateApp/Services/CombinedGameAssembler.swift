//
//  CombinedGameAssembler.swift
//  LicensePlateApp
//
//  Step 06 — Builds game instances for a trip session from combined game configuration. No persistence; caller uses repositories.
//  Step 07.5 — commonConfig and license_plate payload. Step 6.9.2 — LP config from caller, not TripSession.
//

import Foundation

/// Assembles one GameInstance per enabled game type for a given TripSession. Caller persists via GameInstanceRepository.
enum CombinedGameAssembler {
    /// Create one GameInstance per enabled (and available) game type, all linked to the given session.
    /// - Parameters:
    ///   - session: The trip session these games belong to.
    ///   - config: Which game types are enabled; only available types are used.
    ///   - licensePlateConfig: Optional LP config for license-plate games; when nil, North America default is used.
    /// - Returns: Domain GameInstance values; caller must persist via GameInstanceRepository.
    static func assemble(session: TripSession, config: CombinedGameConfiguration, licensePlateConfig: LicensePlateGameConfig? = nil) -> [GameInstance] {
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

        let defaultLPConfig = LicensePlateGameConfig(
            regionScope: .northAmerica,
            territoryOptions: LicensePlateTerritoryOptions(includeUSTerritories: true, includeCanadianTerritories: true, includeDC: true)
        )

        return types.map { gameType in
            var payloadType: String?
            var payloadVersion: String?
            var payloadData: Data?
            if gameType == .licensePlate {
                let lpConfig = licensePlateConfig ?? defaultLPConfig
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

    /// Build LicensePlateGameConfig from selected countries (for setup flow). Step 6.9.2.
    static func licensePlateConfig(from countries: [PlateRegion.Country]) -> LicensePlateGameConfig {
        let scope = regionScope(from: countries)
        let territoryOptions = LicensePlateTerritoryOptions(
            includeUSTerritories: true,
            includeCanadianTerritories: true,
            includeDC: true
        )
        return LicensePlateGameConfig(regionScope: scope, territoryOptions: territoryOptions)
    }

    /// Default game mode when assembling from trip. TripMode is solo/multiplayer only; game mode defaults to collaborative.
    private static func gameMode(from tripMode: TripMode) -> GameMode {
        _ = tripMode
        return .collaborative
    }

    private static func regionScope(from countries: [PlateRegion.Country]) -> RegionScope {
        let set = Set(countries)
        if set == [.unitedStates] { return .usOnly }
        if set == [.canada] { return .canadaOnly }
        if set == [.mexico] { return .mexicoOnly }
        return .northAmerica
    }
}
