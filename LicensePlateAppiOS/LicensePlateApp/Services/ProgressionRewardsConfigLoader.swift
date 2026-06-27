//
//  ProgressionRewardsConfigLoader.swift
//  LicensePlateApp
//
//  Loads bundled progression rewards JSON, validates, and merges presentation overrides.
//

import Foundation

enum ProgressionRewardsConfigValidationResult: Equatable, Sendable {
    case valid
    case invalid(reason: String)
}

enum ProgressionRewardsConfigValidator {

    private static let maxXpValue = 1_000
    private static let minVisualBandSize = 10
    private static let maxVisualBandSize = 500
    private static let minXpPerRankLevel = 100
    private static let maxXpPerRankLevel = 100_000

    static func validate(_ config: ProgressionRewardsConfig) -> ProgressionRewardsConfigValidationResult {
        guard ProgressionRewardsConfig.supportedSchemaVersions.contains(config.schemaVersion) else {
            return .invalid(reason: "unsupported_schema_version")
        }
        if let reason = validateXp(config.xp) { return .invalid(reason: reason) }
        if let reason = validatePolicy(config.policy) { return .invalid(reason: reason) }
        if let reason = validatePresentation(config.presentation) { return .invalid(reason: reason) }
        return .valid
    }

    static func validatePresentationOverride(_ presentation: ProgressionPresentationRewards) -> ProgressionRewardsConfigValidationResult {
        if let reason = validatePresentation(presentation) { return .invalid(reason: reason) }
        return .valid
    }

    private static func validateXp(_ xp: ProgressionXpRewards) -> String? {
        let fields: [(String, Int)] = [
            ("baseDiscoveryXp", xp.baseDiscoveryXp),
            ("firstFinderBonusXp", xp.firstFinderBonusXp),
            ("firstPlateFindBonusXp", xp.firstPlateFindBonusXp),
            ("baseMultiplayerGameBonusXp", xp.baseMultiplayerGameBonusXp),
            ("competitiveFirstPlaceFinishBonusXp", xp.competitiveFirstPlaceFinishBonusXp),
            ("competitiveSecondPlaceFinishBonusXp", xp.competitiveSecondPlaceFinishBonusXp),
            ("competitiveThirdPlaceFinishBonusXp", xp.competitiveThirdPlaceFinishBonusXp),
            ("gameContributorBonusXp", xp.gameContributorBonusXp),
            ("tripContributorBonusXp", xp.tripContributorBonusXp),
            ("firstTripCompletionBonusXp", xp.firstTripCompletionBonusXp),
            ("firstMultiplayerTripCompletionBonusXp", xp.firstMultiplayerTripCompletionBonusXp),
            ("firstGameCompletionBonusXp", xp.firstGameCompletionBonusXp),
            ("firstMultiplayerGameCompletionBonusXp", xp.firstMultiplayerGameCompletionBonusXp),
            ("baseMilestoneBonusXp", xp.baseMilestoneBonusXp),
        ]
        for (name, value) in fields where value < 0 || value > maxXpValue {
            return "xp_\(name)_out_of_range"
        }
        return nil
    }

    private static func validatePolicy(_ policy: ProgressionPolicyRewards) -> String? {
        if policy.minimumLocalReconciliationDelta < 0 {
            return "policy_minimumLocalReconciliationDelta_negative"
        }
        return nil
    }

    private static func validatePresentation(_ presentation: ProgressionPresentationRewards) -> String? {
        if presentation.visualBandSize < minVisualBandSize || presentation.visualBandSize > maxVisualBandSize {
            return "presentation_visualBandSize_out_of_range"
        }
        if presentation.xpPerRankLevel < minXpPerRankLevel || presentation.xpPerRankLevel > maxXpPerRankLevel {
            return "presentation_xpPerRankLevel_out_of_range"
        }
        return nil
    }
}

enum ProgressionRewardsConfigLoader {

    static let bundledResourceName = "ProgressionRewardsConfig.v1"
    static let bundledResourceExtension = "json"

    /// Loads and validates bundled JSON; falls back to `bundledDefault` on any failure.
    static func loadBundled(bundle: Bundle = .main) -> ProgressionRewardsConfig {
        guard let url = bundle.url(
            forResource: bundledResourceName,
            withExtension: bundledResourceExtension
        ) else {
            return .bundledDefault
        }
        return load(from: url) ?? .bundledDefault
    }

    /// Decodes JSON from disk and validates; returns nil on failure.
    static func load(from url: URL) -> ProgressionRewardsConfig? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }

    /// Decodes JSON data and validates; returns nil on failure.
    static func decode(_ data: Data) -> ProgressionRewardsConfig? {
        let decoder = JSONDecoder()
        guard let config = try? decoder.decode(ProgressionRewardsConfig.self, from: data) else {
            return nil
        }
        guard case .valid = ProgressionRewardsConfigValidator.validate(config) else {
            return nil
        }
        return config
    }

    /// Merges optional presentation-only Remote Config JSON into bundled config.
    /// XP and policy always come from `bundled`; invalid override JSON is ignored.
    static func merge(
        bundled: ProgressionRewardsConfig,
        presentationOverrideJSON: String?
    ) -> ProgressionRewardsConfig {
        guard let presentationOverrideJSON,
              !presentationOverrideJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let data = presentationOverrideJSON.data(using: .utf8),
              let override = try? JSONDecoder().decode(ProgressionPresentationRewards.self, from: data),
              case .valid = ProgressionRewardsConfigValidator.validatePresentationOverride(override)
        else {
            return bundled
        }

        var merged = bundled
        merged.presentation = override
        return merged
    }
}
