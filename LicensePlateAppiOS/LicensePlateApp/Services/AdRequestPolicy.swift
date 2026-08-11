//
//  AdRequestPolicy.swift
//  LicensePlateApp
//
//  Privacy Policy §8 (Advertising) / §12 (Children) compliance —
//  non-personalized, G-rated ad requests for everyone; child-directed
//  treatment carried per session (COPPA F-7, FR-17).
//

import Foundation

/// Pure decision logic for how every ad request is configured.
///
/// Posture: no personalized ads for anyone and G-rated ad content only. Because no
/// tracking occurs under this posture, no AppTrackingTransparency prompt is required.
///
/// The child-directed signal is part of the policy so `AdMobService.makeRequest()`
/// and the global `RequestConfiguration` derive from the same value and can never
/// disagree (SRS §9.2). Under FR-19 no child/held session should request an ad at
/// all — TFCD here is defense-in-depth.
struct AdRequestPolicy: Equatable {
    /// Whether ad requests may be personalized. Always false.
    let allowsPersonalizedAds: Bool

    /// Maximum ad content rating, mirroring GADMaxAdContentRating raw values
    /// ("G" == MaxAdContentRating.general). AdMobService applies this via the SDK's
    /// typed constant; the coupling is pinned by a test.
    let maxContentRating: String

    /// FR-17: whether `tagForChildDirectedTreatment` is stamped on the global
    /// request configuration for this session. TFUA is never set.
    let childDirected: Bool

    /// The only constructor ad code uses: npa=1 + "G" for everyone; only the
    /// child-directed signal varies per session.
    static func policy(childDirected: Bool) -> AdRequestPolicy {
        AdRequestPolicy(
            allowsPersonalizedAds: false,
            maxContentRating: "G",
            childDirected: childDirected
        )
    }

    /// AdMob network-extras parameters implementing this policy.
    /// "npa": "1" is Google's non-personalized-ads signal.
    var additionalParameters: [String: String] {
        allowsPersonalizedAds ? [:] : ["npa": "1"]
    }
}
