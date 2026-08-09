import Foundation
import Testing
@testable import LicensePlateApp

struct AdRequestPolicyTests {
    @Test func currentPolicyNeverPersonalizes() {
        #expect(AdRequestPolicy.current.allowsPersonalizedAds == false)
    }

    @Test func currentPolicyRequestsGeneralRatedContentOnly() {
        #expect(AdRequestPolicy.current.maxContentRating == "G")
    }

    @Test func currentPolicyCarriesNonPersonalizedAdsSignal() {
        #expect(AdRequestPolicy.current.additionalParameters == ["npa": "1"])
    }

    @Test func personalizedPolicyWouldOmitNpaSignal() {
        let policy = AdRequestPolicy(allowsPersonalizedAds: true, maxContentRating: "G")
        #expect(policy.additionalParameters.isEmpty)
    }
}
