//
//  ProgressionCatalogProvider.swift
//  LicensePlateApp
//
//  Single injection point for bundled achievement + rank catalog (Phase 2).
//

import Foundation

protocol ProgressionCatalogProviding: Sendable {
    var current: ProgressionCatalog { get }
    func refresh(presentationOverrideJSON: String?, xpToastOverrideJSON: String?)
}

extension ProgressionCatalogProviding {
    func refresh(presentationOverrideJSON: String?) {
        refresh(presentationOverrideJSON: presentationOverrideJSON, xpToastOverrideJSON: nil)
    }
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

    /// Reloads bundled JSON and merges optional Remote Config presentation / xpToast overrides.
    func refresh(presentationOverrideJSON: String? = nil, xpToastOverrideJSON: String? = nil) {
        let bundled = ProgressionCatalogLoader.loadBundled()
        let trimmedPresentation = presentationOverrideJSON?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedXpToast = xpToastOverrideJSON?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hasPresentationOverride = !(trimmedPresentation?.isEmpty ?? true)
        let hasXpToastOverride = !(trimmedXpToast?.isEmpty ?? true)

        let previous = current
        let merged: ProgressionCatalog
        if hasPresentationOverride || hasXpToastOverride {
            merged = ProgressionCatalogLoader.merge(
                bundled: bundled,
                presentationOverrideJSON: trimmedPresentation,
                xpToastOverrideJSON: trimmedXpToast
            )
            if hasPresentationOverride,
               merged.presentation == bundled.presentation {
                logFallback(reason: "invalid_presentation_override")
            } else if hasPresentationOverride,
                      merged.presentation != previous.presentation {
                logPresentationOverrideApplied(merged.presentation)
            }
            if hasXpToastOverride,
               merged.xpToast == bundled.xpToast {
                logFallback(reason: "invalid_xp_toast_override")
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
