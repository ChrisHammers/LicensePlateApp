//
//  AdMobService.swift
//  LicensePlateApp
//
//  Step 18 — Google Mobile Ads bootstrap and ad unit lookup.
//  COPPA F-7 (FR-17/FR-19): sole writer of tagForChildDirectedTreatment; the
//  cached child signal / device ratchet is stamped BEFORE MobileAds.start().
//

import Foundation

#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

@MainActor
final class AdMobService {
    static let shared = AdMobService()

    private var hasStarted = false

    /// The last child-directed treatment applied to the global request
    /// configuration. `makeRequest()` derives its policy from this same value, so
    /// the request path and the global config can never disagree (SRS §9.2).
    /// Fail-closed default: child-directed until a posture is applied.
    private(set) var appliedChildDirectedTreatment = true

    private init() {}

    /// FR-19/FR-39 pre-start stamp: child-directed at cold start when the device
    /// ratchet is set, any uid's cached flag is true, or this device ever declared
    /// a child registration. Runs before auth resolves — per-identity postures
    /// re-stamp at the FR-23 seam.
    static func preStartChildDirected(
        isDeviceRatcheted: Bool,
        hasAnyCachedChildTrue: Bool,
        hasDeclaredChildHistory: Bool
    ) -> Bool {
        isDeviceRatcheted || hasAnyCachedChildTrue || hasDeclaredChildHistory
    }

    /// The current per-session request policy (npa=1 + "G" for everyone; the
    /// child-directed signal follows the applied global config).
    var currentRequestPolicy: AdRequestPolicy {
        .policy(childDirected: appliedChildDirectedTreatment)
    }

    /// FR-17: the ONLY writer of `tagForChildDirectedTreatment` in the app.
    /// true for child/ratcheted sessions; nil (unset) for resolved adults.
    /// `tagForUnderAgeOfConsent` is never set — TFCD and TFUA must not coexist.
    func applyChildDirectedTreatment(_ childDirected: Bool) {
        appliedChildDirectedTreatment = childDirected
        #if canImport(GoogleMobileAds)
        let configuration = MobileAds.shared.requestConfiguration
        configuration.tagForChildDirectedTreatment = childDirected ? NSNumber(value: true) : nil
        configuration.tagForUnderAgeOfConsent = nil
        #endif
    }

    func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        #if canImport(GoogleMobileAds)
        // FR-19 asymmetric cache + FR-39 ratchet: stamped BEFORE the SDK starts so a
        // cold start on a device that ever hosted a child never builds an untagged
        // request. Adult sessions are un-stamped at the FR-23 seam once confirmed.
        applyChildDirectedTreatment(Self.preStartChildDirected(
            isDeviceRatcheted: ChildSignalCache.shared.isDeviceRatcheted,
            hasAnyCachedChildTrue: ChildSignalCache.shared.hasAnyCachedChildTrue,
            hasDeclaredChildHistory: AgeGateStore.shared.hasDeclaredChildHistory
        ))
        // G-rated creatives only, per AdRequestPolicy (Privacy Policy §8/§12).
        MobileAds.shared.requestConfiguration.maxAdContentRating =
            Self.sdkMaxAdContentRating(for: currentRequestPolicy)
        MobileAds.shared.start()
        #endif
    }

    #if canImport(GoogleMobileAds)
    /// Pins the "G" string in `AdRequestPolicy` to the SDK's `.general` constant
    /// (the two must stay in sync; covered by a test).
    static func sdkMaxAdContentRating(for policy: AdRequestPolicy) -> GADMaxAdContentRating {
        assert(policy.maxContentRating == "G", "AdRequestPolicy rating drifted from the SDK mapping")
        return .general
    }

    /// The only way ad surfaces may build a request. Carries the
    /// non-personalized-ads signal from `AdRequestPolicy` so no view
    /// constructs ad policy itself.
    func makeRequest() -> Request {
        let request = Request()
        let extras = Extras()
        extras.additionalParameters = currentRequestPolicy.additionalParameters
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
