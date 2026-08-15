//
//  AdMobService.swift
//  LicensePlateApp
//
//  Step 18 — Google Mobile Ads bootstrap and ad unit lookup.
//  COPPA F-7 (FR-17/FR-19): sole writer of tagForChildDirectedTreatment; the
//  posture is stamped BEFORE MobileAds.start().
//  COPPA F-15 (FR-56): the SDK is no longer started at launch. It starts from the
//  `DeferredSDKStartupService` gate, for a resolved `.confirmedNonChild` posture only,
//  and any start without that positive adult evidence is tagged child-directed.
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

    /// FR-56 pre-start stamp, inverted: a start is UNTAGGED only on positive ADULT
    /// evidence — this session's posture resolved to `.confirmedNonChild`. Every other
    /// start is tagged child-directed, `.unresolved` included, because SDK
    /// initialization is itself a data event to the ad network and the FR-19 display
    /// hold governs requests, not initialization.
    ///
    /// Device-level child evidence (FR-19 cached-true, FR-39 ratchet, declared history)
    /// no longer needs a clause of its own: it can only ever produce a non-adult
    /// posture, which this already tags. Keeping the posture as the single input also
    /// keeps this in agreement with `ChildSessionPosture.childDirectedTreatment`, the
    /// stamp the posture routine applies — two writers of TFCD that could disagree is
    /// exactly what FR-17 forbids.
    static func preStartChildDirected(posture: ChildSessionPosture) -> Bool {
        posture != .confirmedNonChild
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

    /// FR-56: called ONLY from the deferred-startup gate, which releases ads for a
    /// resolved `.confirmedNonChild` posture — never from `didFinishLaunching`. The
    /// posture is the caller's, so the stamp lands BEFORE `start()` in every case.
    func startIfNeeded(posture: ChildSessionPosture) {
        guard !hasStarted else { return }
        hasStarted = true
        #if canImport(GoogleMobileAds)
        applyChildDirectedTreatment(Self.preStartChildDirected(posture: posture))
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
