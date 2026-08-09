//
//  AdRequestPolicy.swift
//  LicensePlateApp
//
//  Privacy Policy §8 (Advertising) / §12 (Children) compliance —
//  non-personalized, G-rated ad requests for everyone.
//

import Foundation

/// Pure decision logic for how every ad request is configured.
///
/// Current posture: no personalized ads for anyone and G-rated ad content
/// only. Because no tracking occurs under this posture, no
/// AppTrackingTransparency prompt is required.
///
/// This is the single place ad-request policy lives. Extend it here with a
/// per-user child-account signal (tagForChildDirectedTreatment /
/// tagForUnderAgeOfConsent) when one exists — never in views.
struct AdRequestPolicy: Equatable {
    /// Whether ad requests may be personalized. Always false today.
    let allowsPersonalizedAds: Bool

    /// Maximum ad content rating, mirroring GADMaxAdContentRating raw values
    /// ("G" == GADMaxAdContentRatingGeneral). AdMobService applies this via
    /// the SDK's typed constant; the two must stay in sync.
    let maxContentRating: String

    /// The posture applied to every ad request in the app.
    static let current = AdRequestPolicy(allowsPersonalizedAds: false, maxContentRating: "G")

    /// AdMob network-extras parameters implementing this policy.
    /// "npa": "1" is Google's non-personalized-ads signal.
    var additionalParameters: [String: String] {
        allowsPersonalizedAds ? [:] : ["npa": "1"]
    }
}
