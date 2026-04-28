//
//  AdMobService.swift
//  LicensePlateApp
//
//  Step 18 — Google Mobile Ads bootstrap and ad unit lookup.
//

import Foundation

#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

@MainActor
final class AdMobService {
    static let shared = AdMobService()

    private var hasStarted = false

    private init() {}

    func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        #if canImport(GoogleMobileAds)
        MobileAds.shared.start()
        #endif
    }

    func adUnitId(for surface: AdSurface) -> String {
        let key: String
        let debugFallback: String
        switch surface {
        case .combinedTripSetup:
            key = "AdMobBannerSetupID"
            debugFallback = "ca-app-pub-3940256099942544/2934735716"
        case .travelLog:
            key = "AdMobBannerTravelLogID"
            debugFallback = "ca-app-pub-3940256099942544/2934735716"
        case .tripSummary:
            key = "AdMobBannerSummaryID"
            debugFallback = "ca-app-pub-3940256099942544/2934735716"
        }

        if let configured = Bundle.main.object(forInfoDictionaryKey: key) as? String,
           !configured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return configured
        }

        #if DEBUG
        return debugFallback
        #else
        return ""
        #endif
    }
}
