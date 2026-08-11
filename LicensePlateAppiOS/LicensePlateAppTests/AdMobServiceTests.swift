//
//  AdMobServiceTests.swift
//  LicensePlateAppTests
//
//  COPPA F-7 (FR-17): AdMobService is the only TFCD writer; TFUA is never set;
//  the "G" policy string is pinned to the SDK's .general constant; the request
//  path and global config derive from the same applied value.
//

import Foundation
import Testing
@testable import LicensePlateApp

#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

@MainActor
struct AdMobServiceTests {

    @Test func applyChildDirectedTrueStampsTfcdAndMirrorsRequestPolicy() {
        let service = AdMobService.shared
        service.applyChildDirectedTreatment(true)
        #expect(service.appliedChildDirectedTreatment == true)
        #expect(service.currentRequestPolicy == AdRequestPolicy.policy(childDirected: true))
        #if canImport(GoogleMobileAds)
        #expect(MobileAds.shared.requestConfiguration.tagForChildDirectedTreatment == NSNumber(value: true))
        #endif
    }

    @Test func applyChildDirectedFalseResetsTfcdToUnset() {
        let service = AdMobService.shared
        service.applyChildDirectedTreatment(true)
        service.applyChildDirectedTreatment(false)
        #expect(service.appliedChildDirectedTreatment == false)
        #expect(service.currentRequestPolicy == AdRequestPolicy.policy(childDirected: false))
        #if canImport(GoogleMobileAds)
        // Resolved adults are UNSET (nil), never an explicit false certification.
        #expect(MobileAds.shared.requestConfiguration.tagForChildDirectedTreatment == nil)
        #endif
    }

    @Test func tfuaIsNeverSetInEitherDirection() {
        let service = AdMobService.shared
        service.applyChildDirectedTreatment(true)
        #if canImport(GoogleMobileAds)
        #expect(MobileAds.shared.requestConfiguration.tagForUnderAgeOfConsent == nil)
        #endif
        service.applyChildDirectedTreatment(false)
        #if canImport(GoogleMobileAds)
        #expect(MobileAds.shared.requestConfiguration.tagForUnderAgeOfConsent == nil)
        #endif
    }

    @Test func gRatingStaysPinnedToSdkGeneralConstant() {
        #if canImport(GoogleMobileAds)
        let rating = AdMobService.sdkMaxAdContentRating(for: .policy(childDirected: false))
        #expect(rating == .general)
        #expect((rating.rawValue as String) == AdRequestPolicy.policy(childDirected: true).maxContentRating)
        #endif
    }

    // MARK: - Pre-start stamp (FR-19 cached-true / FR-39 ratchet)

    @Test func preStartIsChildDirectedWhenRatcheted() {
        #expect(AdMobService.preStartChildDirected(
            isDeviceRatcheted: true, hasAnyCachedChildTrue: false, hasDeclaredChildHistory: false
        ) == true)
    }

    @Test func preStartIsChildDirectedWhenAnyCachedTrue() {
        #expect(AdMobService.preStartChildDirected(
            isDeviceRatcheted: false, hasAnyCachedChildTrue: true, hasDeclaredChildHistory: false
        ) == true)
    }

    @Test func preStartIsChildDirectedWhenDeviceEverDeclaredAChild() {
        #expect(AdMobService.preStartChildDirected(
            isDeviceRatcheted: false, hasAnyCachedChildTrue: false, hasDeclaredChildHistory: true
        ) == true)
    }

    @Test func preStartIsUntaggedOnACleanDevice() {
        // Cold-start gap on a clean device is closed by the FR-19 display hold, not
        // by tagging: nil = untagged until the identity posture resolves.
        #expect(AdMobService.preStartChildDirected(
            isDeviceRatcheted: false, hasAnyCachedChildTrue: false, hasDeclaredChildHistory: false
        ) == false)
    }
}
