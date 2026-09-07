//
//  ReviewPromptService.swift
//  LicensePlateApp
//
//  Step 18 — Review prompt strategy with cooldowns and sensible triggers.
//

import Foundation
import StoreKit
import UIKit

protocol ReviewPromptPresenting {
    func requestReview()
}

struct StoreKitReviewPromptPresenter: ReviewPromptPresenting {
    func requestReview() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else {
            return
        }
        SKStoreReviewController.requestReview(in: scene)
    }
}

@MainActor
final class ReviewPromptService {
    static let shared = ReviewPromptService(
        remoteConfig: RemoteConfigService.shared,
        presenter: StoreKitReviewPromptPresenter()
    )

    private enum DefaultsKey {
        static let completedTripCount = "reviewPrompt.completedTripCount"
        static let lastPromptAt = "reviewPrompt.lastPromptAt"
    }

    private let remoteConfig: RemoteConfigValueProviding
    private let presenter: ReviewPromptPresenting
    private let defaults: UserDefaults
    private let now: () -> Date
    /// FR-79 (F-35): the review prompt is a public/commercial exit (it can hand a
    /// child's device to the App Store or the system review sheet), so it gets the
    /// same asymmetric trust as ads and purchases (FR-19) — only a fresh-confirmed
    /// adult session may be prompted. Injectable so tests can drive posture without
    /// touching the live `ChildSessionPostureCoordinator` singleton.
    private let posture: () -> ChildSessionPosture

    init(
        remoteConfig: RemoteConfigValueProviding,
        presenter: ReviewPromptPresenting,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        posture: (() -> ChildSessionPosture)? = nil
    ) {
        self.remoteConfig = remoteConfig
        self.presenter = presenter
        self.defaults = defaults
        self.now = now
        // Resolved in the body, not as a default argument: default-argument
        // expressions are nonisolated, and `currentPosture` is MainActor.
        self.posture = posture ?? { ChildSessionPostureCoordinator.shared.currentPosture }
    }

    func considerPromptAfterTripCompleted(sessionId: UUID) {
        // FR-79 (F-35): no-op in full for any non-confirmedNonChild posture — no
        // completed-trip count, no remote-config check, no analytics, no prompt. A
        // child-directed session must never accumulate state toward, or fire, a
        // public/commercial exit. Deliberately silent: FR-21 forbids an event that
        // fires only for child sessions on the child's own instance, so this branch
        // logs nothing (unlike the suppression branches below, which log a reason and
        // are reachable by every posture).
        guard !posture().suppressesUnmanagedExits else { return }

        let completedCount = defaults.integer(forKey: DefaultsKey.completedTripCount) + 1
        defaults.set(completedCount, forKey: DefaultsKey.completedTripCount)

        guard remoteConfig.bool(for: .reviewPromptEnabled) else {
            AnalyticsService.shared.log(.reviewPromptSuppressed(reason: "remote_config_disabled", completedTripCount: completedCount))
            return
        }
        guard completedCount >= max(1, remoteConfig.int(for: .reviewPromptMinimumCompletedTrips)) else {
            AnalyticsService.shared.log(.reviewPromptSuppressed(reason: "below_completed_trip_threshold", completedTripCount: completedCount))
            return
        }
        if let lastPromptAt = defaults.object(forKey: DefaultsKey.lastPromptAt) as? Date {
            let cooldown = TimeInterval(max(1, remoteConfig.int(for: .reviewPromptCooldownDays)) * 86_400)
            guard now().timeIntervalSince(lastPromptAt) >= cooldown else {
                AnalyticsService.shared.log(.reviewPromptSuppressed(reason: "cooldown", completedTripCount: completedCount))
                return
            }
        }

        AnalyticsService.shared.log(.reviewPromptEligible(completedTripCount: completedCount))
        presenter.requestReview()
        defaults.set(now(), forKey: DefaultsKey.lastPromptAt)
        AnalyticsService.shared.log(.reviewPromptPresented(sessionId: sessionId.uuidString))
    }
}
