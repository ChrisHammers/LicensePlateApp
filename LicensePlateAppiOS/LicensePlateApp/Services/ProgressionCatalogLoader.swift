//
//  ProgressionCatalogLoader.swift
//  LicensePlateApp
//
//  Loads bundled progression catalog JSON, validates, and merges presentation overrides.
//

import Foundation

enum ProgressionCatalogValidationResult: Equatable, Sendable {
    case valid
    case invalid(reason: String)
}

enum ProgressionCatalogValidator {

    private static let maxXpReward = 10_000
    private static let maxGoal = 100_000

    static func validate(_ catalog: ProgressionCatalog) -> ProgressionCatalogValidationResult {
        guard ProgressionCatalog.supportedSchemaVersions.contains(catalog.schemaVersion) else {
            return .invalid(reason: "unsupported_schema_version")
        }
        if let reason = validateAchievements(catalog.achievements) { return .invalid(reason: reason) }
        if let reason = validateRankLadder(catalog.rankLadder) { return .invalid(reason: reason) }
        return .valid
    }

    static func validatePresentationOverride(_ presentation: ProgressionCatalogPresentation) -> ProgressionCatalogValidationResult {
        .valid
    }

    private static func validateAchievements(_ achievements: [ProgressionCatalogAchievement]) -> String? {
        var seenIds = Set<String>()
        for achievement in achievements {
            if achievement.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "achievement_id_empty"
            }
            if !seenIds.insert(achievement.id).inserted {
                return "achievement_duplicate_id"
            }
            if achievement.titleKey.isEmpty || achievement.detailKey.isEmpty {
                return "achievement_localization_key_empty"
            }
            if achievement.icon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "achievement_icon_empty"
            }
            if achievement.goal < 1 || achievement.goal > maxGoal {
                return "achievement_goal_out_of_range"
            }
            if achievement.xpReward < 0 || achievement.xpReward > maxXpReward {
                return "achievement_xpReward_out_of_range"
            }
            if ProgressionCatalogAchievementEvaluator.deferredEvaluators.contains(achievement.evaluator),
               !achievement.hidden {
                return "achievement_deferred_evaluator_must_be_hidden"
            }
        }
        return nil
    }

    private static func validateRankLadder(_ ladder: ProgressionCatalogRankLadder) -> String? {
        guard !ladder.ranks.isEmpty else { return "rank_ladder_empty" }

        var seenLevels = Set<Int>()
        var previousThreshold = -1

        for rank in ladder.ranks.sorted(by: { $0.level < $1.level }) {
            if rank.level < 1 {
                return "rank_level_invalid"
            }
            if !seenLevels.insert(rank.level).inserted {
                return "rank_duplicate_level"
            }
            if rank.titleKey.isEmpty {
                return "rank_title_key_empty"
            }
            if rank.xpRequired < 0 {
                return "rank_xpRequired_negative"
            }
            if rank.xpRequired < previousThreshold {
                return "rank_xpRequired_not_monotonic"
            }
            previousThreshold = rank.xpRequired

            for unlock in rank.unlocks {
                if unlock.titleKey.isEmpty {
                    return "rank_unlock_title_key_empty"
                }
                if unlock.icon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return "rank_unlock_icon_empty"
                }
            }
        }

        guard ladder.ranks.contains(where: { $0.level == 1 && $0.xpRequired == 0 }) else {
            return "rank_level_one_must_start_at_zero_xp"
        }

        return nil
    }
}

enum ProgressionCatalogLoader {

    static let bundledResourceName = "ProgressionCatalog.v1"
    static let bundledResourceExtension = "json"

    /// Loads and validates bundled JSON; falls back to `bundledDefault` on any failure.
    static func loadBundled(bundle: Bundle = .main) -> ProgressionCatalog {
        guard let url = bundle.url(
            forResource: bundledResourceName,
            withExtension: bundledResourceExtension
        ) else {
            return .bundledDefault
        }
        return load(from: url) ?? .bundledDefault
    }

    /// Decodes JSON from disk and validates; returns nil on failure.
    static func load(from url: URL) -> ProgressionCatalog? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }

    /// Decodes JSON data and validates; returns nil on failure.
    static func decode(_ data: Data) -> ProgressionCatalog? {
        let decoder = JSONDecoder()
        guard let catalog = try? decoder.decode(ProgressionCatalog.self, from: data) else {
            return nil
        }
        guard case .valid = ProgressionCatalogValidator.validate(catalog) else {
            return nil
        }
        return catalog
    }

    /// Merges optional presentation-only Remote Config JSON into bundled catalog.
    /// Achievements and rank ladder always come from `bundled`; invalid override JSON is ignored.
    static func merge(
        bundled: ProgressionCatalog,
        presentationOverrideJSON: String?
    ) -> ProgressionCatalog {
        guard let presentationOverrideJSON,
              !presentationOverrideJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let data = presentationOverrideJSON.data(using: .utf8),
              let override = try? JSONDecoder().decode(ProgressionCatalogPresentation.self, from: data),
              case .valid = ProgressionCatalogValidator.validatePresentationOverride(override)
        else {
            return bundled
        }

        var merged = bundled
        merged.presentation = override
        return merged
    }
}
