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

    init(
        remoteConfig: RemoteConfigValueProviding,
        presenter: ReviewPromptPresenting,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        self.remoteConfig = remoteConfig
        self.presenter = presenter
        self.defaults = defaults
        self.now = now
    }

    func considerPromptAfterTripCompleted(sessionId: UUID) {
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
