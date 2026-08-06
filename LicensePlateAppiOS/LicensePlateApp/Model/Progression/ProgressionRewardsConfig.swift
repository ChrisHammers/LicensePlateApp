//
//  ProgressionRewardsConfig.swift
//  LicensePlateApp
//
//  Typed, versioned progression rewards table (Phase 1 lite).
//  Authoritative XP values must stay aligned with functions/src/progressionXpAmounts.ts.
//

import Foundation

// MARK: - Root config

struct ProgressionRewardsConfig: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var xp: ProgressionXpRewards
    var policy: ProgressionPolicyRewards
    var presentation: ProgressionPresentationRewards

    static let supportedSchemaVersions: Set<Int> = [1]
}

// MARK: - XP rewards

struct ProgressionXpRewards: Codable, Equatable, Sendable {
    var baseDiscoveryXp: Int
    var firstFinderBonusXp: Int
    var lifetimeUniqueRegionFindBonusXp: Int
    var firstFindOfDayBonusXp: Int
    var competitiveFirstPlaceFinishBonusXp: Int
    var competitiveSecondPlaceFinishBonusXp: Int
    var competitiveThirdPlaceFinishBonusXp: Int
    var gameEndedBonusXp: Int
    var gameFullClearBonusXp: Int
    var tripEndedBonusXp: Int
    var tripParticipationBonusXp: Int
    var tripCompetitiveFirstPlaceBonusXp: Int
}

// MARK: - Policy

struct ProgressionPolicyRewards: Codable, Equatable, Sendable {
    var minimumLocalReconciliationDelta: Int
}

// MARK: - Presentation (client-only tuning; safe for Remote Config override in Step 3)

struct ProgressionPresentationRewards: Codable, Equatable, Sendable {
    var visualBandSize: Int
    var xpPerRankLevel: Int
}

// MARK: - Defaults

extension ProgressionRewardsConfig {

    /// Hardcoded mirror of `ProgressionRewardsConfig.v1.json`; used when bundle load or validation fails.
    static let bundledDefault = ProgressionRewardsConfig(
        schemaVersion: 1,
        xp: ProgressionXpRewards(
            baseDiscoveryXp: 10,
            firstFinderBonusXp: 5,
            lifetimeUniqueRegionFindBonusXp: 20,
            firstFindOfDayBonusXp: 10,
            competitiveFirstPlaceFinishBonusXp: 25,
            competitiveSecondPlaceFinishBonusXp: 10,
            competitiveThirdPlaceFinishBonusXp: 5,
            gameEndedBonusXp: 50,
            gameFullClearBonusXp: 200,
            tripEndedBonusXp: 100,
            tripParticipationBonusXp: 50,
            tripCompetitiveFirstPlaceBonusXp: 25
        ),
        policy: ProgressionPolicyRewards(minimumLocalReconciliationDelta: 0),
        presentation: ProgressionPresentationRewards(visualBandSize: 100, xpPerRankLevel: 3_000)
    )

    /// Deterministic fixture for unit tests (matches bundled default).
    static let fixtureDefault = bundledDefault
}
