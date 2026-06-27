//
//  ProgressionRewardsConfigProvider.swift
//  LicensePlateApp
//
//  Single injection point for progression rewards config (Phase 1 lite).
//

import Foundation

protocol ProgressionRewardsConfigProviding: Sendable {
    var current: ProgressionRewardsConfig { get }
    func refresh(presentationOverrideJSON: String?)
}

final class ProgressionRewardsConfigProvider: ProgressionRewardsConfigProviding, @unchecked Sendable {

    static let shared = ProgressionRewardsConfigProvider()

    private let lock = NSLock()
    private var cached: ProgressionRewardsConfig

    init(bundle: Bundle = .main) {
        cached = ProgressionRewardsConfigLoader.loadBundled(bundle: bundle)
    }

    var current: ProgressionRewardsConfig {
        lock.lock()
        defer { lock.unlock() }
        return cached
    }

    /// Reloads bundled JSON and merges optional Remote Config presentation override (xp/policy unchanged).
    func refresh(presentationOverrideJSON: String? = nil) {
        let bundled = ProgressionRewardsConfigLoader.loadBundled()
        let trimmedOverride = presentationOverrideJSON?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hasOverride = !(trimmedOverride?.isEmpty ?? true)

        let previous = current
        let merged: ProgressionRewardsConfig
        if hasOverride, let trimmedOverride {
            merged = ProgressionRewardsConfigLoader.merge(
                bundled: bundled,
                presentationOverrideJSON: trimmedOverride
            )
            if merged.presentation == bundled.presentation {
                logFallback(reason: "invalid_presentation_override")
            } else if merged.presentation != previous.presentation {
                logPresentationOverrideApplied(merged.presentation)
            }
        } else {
            merged = bundled
        }

        lock.lock()
        cached = merged
        lock.unlock()
    }

    private func logPresentationOverrideApplied(_ presentation: ProgressionPresentationRewards) {
        Task { @MainActor in
            AnalyticsService.shared.log(
                .progressionRewardsPresentationOverrideApplied(
                    visualBandSize: presentation.visualBandSize,
                    xpPerRankLevel: presentation.xpPerRankLevel
                )
            )
        }
    }

    private func logFallback(reason: String) {
        Task { @MainActor in
            AnalyticsService.shared.log(.progressionRewardsConfigFallback(reason: reason))
        }
    }
}
