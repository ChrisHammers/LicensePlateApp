//
//  AdEligibilityService.swift
//  LicensePlateApp
//
//  Step 18 — Free-tier ad eligibility. No SDK or UI work lives here.
//

import Foundation

enum AdSurface: String, CaseIterable {
    case combinedTripSetup = "combined_trip_setup"
    case travelLog = "travel_log"
    case tripSummary = "trip_summary"
}

@MainActor
final class AdEligibilityService {
    static let shared = AdEligibilityService(
        remoteConfig: RemoteConfigService.shared,
        effectiveTierProvider: { EntitlementService.shared.entitlementState(for: $0).effectiveTier }
    )

    private let remoteConfig: RemoteConfigValueProviding
    private let effectiveTierProvider: (AppUser) -> UserTier
    private var loggedSignatures: Set<String> = []

    init(remoteConfig: RemoteConfigValueProviding, effectiveTierProvider: @escaping (AppUser) -> UserTier) {
        self.remoteConfig = remoteConfig
        self.effectiveTierProvider = effectiveTierProvider
    }

    func shouldShowAd(for surface: AdSurface, user: AppUser?) -> Bool {
        guard remoteConfig.bool(for: .adsEnabledFreeTier) else {
            logEligibility(surface: surface, eligible: false, reason: "remote_config_disabled")
            return false
        }
        guard let user else {
            logEligibility(surface: surface, eligible: true, reason: "no_user_free_tier")
            return true
        }
        let eligible = effectiveTierProvider(user) < .gold
        logEligibility(surface: surface, eligible: eligible, reason: eligible ? "free_tier" : "premium_tier")
        return eligible
    }

    private func logEligibility(surface: AdSurface, eligible: Bool, reason: String) {
        let signature = "\(surface.rawValue)-\(eligible)-\(reason)"
        guard !loggedSignatures.contains(signature) else { return }
        loggedSignatures.insert(signature)
        AnalyticsService.shared.log(.adEligibilityEvaluated(surface: surface.rawValue, eligible: eligible, reason: reason))
    }
}
