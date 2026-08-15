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

    // MARK: - Pre-start stamp (FR-56: untagged only on positive adult evidence)

    /// The inversion itself. The old rule tagged only on positive CHILD evidence, so a
    /// clean install — where the cache, the ratchet and the declared history are all
    /// empty by definition — started the SDK untagged before the age gate had been
    /// shown. Tagging is now the default and adult evidence is the only exit.
    @Test func preStartIsUntaggedOnlyForAConfirmedAdult() {
        #expect(AdMobService.preStartChildDirected(posture: .confirmedNonChild) == false)
        for posture in [ChildSessionPosture.unresolved, .childDirected, .ratchetedAnonymous] {
            #expect(
                AdMobService.preStartChildDirected(posture: posture) == true,
                "\(posture.rawValue) must start tagged child-directed"
            )
        }
    }

    /// The pre-start stamp and the posture routine's stamp must never disagree for the
    /// postures that can actually reach a start (FR-17: one TFCD writer, one value).
    /// They differ only on `.unresolved`, where the pre-start rule is the stricter one.
    @Test func preStartAgreesWithThePostureStampWhereverAStartIsPossible() {
        for posture in [ChildSessionPosture.confirmedNonChild, .childDirected, .ratchetedAnonymous] {
            #expect(AdMobService.preStartChildDirected(posture: posture) == posture.childDirectedTreatment)
        }
        #expect(ChildSessionPosture.unresolved.childDirectedTreatment == false)
        #expect(AdMobService.preStartChildDirected(posture: .unresolved) == true)
    }
}
