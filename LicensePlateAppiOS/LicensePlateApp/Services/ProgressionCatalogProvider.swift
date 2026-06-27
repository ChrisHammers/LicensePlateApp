//
//  ProgressionCatalogProvider.swift
//  LicensePlateApp
//
//  Single injection point for bundled achievement + rank catalog (Phase 2).
//

import Foundation

protocol ProgressionCatalogProviding: Sendable {
    var current: ProgressionCatalog { get }
    func refresh(presentationOverrideJSON: String?)
}

final class ProgressionCatalogProvider: ProgressionCatalogProviding, @unchecked Sendable {

    static let shared = ProgressionCatalogProvider()

    private let lock = NSLock()
    private var cached: ProgressionCatalog

    init(bundle: Bundle = .main) {
        cached = ProgressionCatalogLoader.loadBundled(bundle: bundle)
    }

    var current: ProgressionCatalog {
        lock.lock()
        defer { lock.unlock() }
        return cached
    }

    /// Reloads bundled JSON and merges optional Remote Config presentation override (achievements/ranks unchanged).
    func refresh(presentationOverrideJSON: String? = nil) {
        let bundled = ProgressionCatalogLoader.loadBundled()
        let trimmedOverride = presentationOverrideJSON?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hasOverride = !(trimmedOverride?.isEmpty ?? true)

        let previous = current
        let merged: ProgressionCatalog
        if hasOverride, let trimmedOverride {
            merged = ProgressionCatalogLoader.merge(
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

    private func logPresentationOverrideApplied(_ presentation: ProgressionCatalogPresentation) {
        Task { @MainActor in
            AnalyticsService.shared.log(
                .progressionCatalogPresentationOverrideApplied(
                    achievementsEnabled: presentation.achievementsEnabled,
                    rankProgressionEnabled: presentation.rankProgressionEnabled
                )
            )
        }
    }

    private func logFallback(reason: String) {
        Task { @MainActor in
            AnalyticsService.shared.log(.progressionCatalogConfigFallback(reason: reason))
        }
    }
}
