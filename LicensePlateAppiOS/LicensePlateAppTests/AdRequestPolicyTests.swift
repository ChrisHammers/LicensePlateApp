import Foundation
import Testing
@testable import LicensePlateApp

struct AdRequestPolicyTests {
    @Test func policyNeverPersonalizesForAnyVariant() {
        #expect(AdRequestPolicy.policy(childDirected: false).allowsPersonalizedAds == false)
        #expect(AdRequestPolicy.policy(childDirected: true).allowsPersonalizedAds == false)
    }

    @Test func policyRequestsGeneralRatedContentOnlyForAnyVariant() {
        #expect(AdRequestPolicy.policy(childDirected: false).maxContentRating == "G")
        #expect(AdRequestPolicy.policy(childDirected: true).maxContentRating == "G")
    }

    @Test func policyCarriesNonPersonalizedAdsSignalForAnyVariant() {
        // npa=1 + "G" posture holds for everyone; only the child signal varies.
        #expect(AdRequestPolicy.policy(childDirected: false).additionalParameters == ["npa": "1"])
        #expect(AdRequestPolicy.policy(childDirected: true).additionalParameters == ["npa": "1"])
    }

    @Test func policyCarriesTheChildDirectedVariant() {
        #expect(AdRequestPolicy.policy(childDirected: true).childDirected == true)
        #expect(AdRequestPolicy.policy(childDirected: false).childDirected == false)
    }

    @Test func personalizedPolicyWouldOmitNpaSignal() {
        let policy = AdRequestPolicy(allowsPersonalizedAds: true, maxContentRating: "G", childDirected: false)
        #expect(policy.additionalParameters.isEmpty)
    }
}
