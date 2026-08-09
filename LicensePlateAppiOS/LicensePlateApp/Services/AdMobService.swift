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
        // G-rated creatives only, per AdRequestPolicy (Privacy Policy §8/§12).
        // Mixed-audience app: per-user child flags (tagForChildDirectedTreatment /
        // tagForUnderAgeOfConsent) stay unset until a child-account signal exists.
        MobileAds.shared.requestConfiguration.maxAdContentRating = .general
        MobileAds.shared.start()
        #endif
    }

    #if canImport(GoogleMobileAds)
    /// The only way ad surfaces may build a request. Carries the
    /// non-personalized-ads signal from `AdRequestPolicy` so no view
    /// constructs ad policy itself.
    func makeRequest() -> Request {
        let request = Request()
        let extras = Extras()
        extras.additionalParameters = AdRequestPolicy.current.additionalParameters
        request.register(extras)
        return request
    }
    #endif

    func adUnitId(for surface: AdSurface) -> String {
        let key: String
        let debugFallback: String
        switch surface {
        case .combinedTripSetup, .tripSetup:
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
