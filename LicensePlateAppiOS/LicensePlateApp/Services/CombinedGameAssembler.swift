//
//  CombinedGameAssembler.swift
//  LicensePlateApp
//
//  Step 06 — Builds game instances for a trip session from combined game configuration. No persistence; caller uses repositories.
//  Step 07.5 — commonConfig and license_plate payload. Step 6.9.2 — LP config from caller, not TripSession.
//  Step 6.9.4 — GameMode and teams from `GameSetupChoice`, not from trip participation (roster size).
//

import Foundation

/// Assembles one GameInstance per enabled game type for a given TripSession. Caller persists via GameInstanceRepository.
enum CombinedGameAssembler {
    /// Create one GameInstance per enabled (and available) game type, all linked to the given session.
    /// Uses per-type `choicesByGameType`; missing keys default to collaborative with no teams.
    static func assemble(
        session: TripSession,
        config: CombinedGameConfiguration,
        choicesByGameType: [GameType: GameSetupChoice],
        licensePlateConfig: LicensePlateGameConfig? = nil
    ) -> [GameInstance] {
        let types = config.availableEnabledTypes
        guard !types.isEmpty else { return [] }

        /// Row creation time only; canonical “game started” time is set in `GameInstanceLifecycleService.startGame`.
        let gameAssemblyStartedAt = Date()

        let defaultLPConfig = LicensePlateGameConfig(
            selectedCountriesRawValues: [
                PlateRegion.Country.unitedStates.rawValue,
                PlateRegion.Country.canada.rawValue,
                PlateRegion.Country.mexico.rawValue
            ],
            territoryOptions: LicensePlateTerritoryOptions(includeUSTerritories: true, includeCanadianTerritories: true, includeDC: true)
        )

        return types.map { gameType in
            let choice = choicesByGameType[gameType] ?? GameSetupChoice(gameType: gameType, gameMode: .collaborative, teams: [])
            let commonConfig = CommonGameConfig(
                lifecycleState: .created,
                gameMode: choice.gameMode,
                scoringProfile: "default",
                configVersion: "1",
                summaryVisibility: true,
                configLocked: false,
                configLockReason: .none
            )

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
                startedAt: gameAssemblyStartedAt,
                endedAt: session.endedAt,
                ruleSet: gameType.defaultRuleSet(),
                commonConfig: commonConfig,
                gameSpecificPayloadType: payloadType,
                gameSpecificPayloadVersion: payloadVersion,
                gameSpecificPayloadData: payloadData,
                teams: choice.teams
            )
        }
    }

    /// Default choices: collaborative mode, no teams, for each enabled available type.
    static func assemble(session: TripSession, config: CombinedGameConfiguration, licensePlateConfig: LicensePlateGameConfig? = nil) -> [GameInstance] {
        let types = config.availableEnabledTypes
        var choices: [GameType: GameSetupChoice] = [:]
        for t in types {
            choices[t] = GameSetupChoice(gameType: t, gameMode: .collaborative, teams: [])
        }
        return assemble(session: session, config: config, choicesByGameType: choices, licensePlateConfig: licensePlateConfig)
    }

    /// Build LicensePlateGameConfig from selected countries with default territory options (all on). Step 6.9.2.
    static func licensePlateConfig(from countries: [PlateRegion.Country]) -> LicensePlateGameConfig {
        licensePlateConfig(from: countries, territoryOptions: LicensePlateTerritoryOptions())
    }

    /// Build LicensePlateGameConfig; `territoryOptions` are normalized so flags cannot apply without their parent country.
    static func licensePlateConfig(from countries: [PlateRegion.Country], territoryOptions: LicensePlateTerritoryOptions) -> LicensePlateGameConfig {
        let normalized = normalizedTerritoryOptions(territoryOptions, forCountries: countries)
        return LicensePlateGameConfig(
            selectedCountriesRawValues: countries.map(\.rawValue),
            territoryOptions: normalized
        )
    }

    /// Forces US territory / DC off when US is not selected; Canadian territories off when Canada is not selected.
    static func normalizedTerritoryOptions(_ options: LicensePlateTerritoryOptions, forCountries countries: [PlateRegion.Country]) -> LicensePlateTerritoryOptions {
        let set = Set(countries)
        var out = options
        if !set.contains(.unitedStates) {
            out.includeUSTerritories = false
            out.includeDC = false
        }
        if !set.contains(.canada) {
            out.includeCanadianTerritories = false
        }
        return out
    }
}
