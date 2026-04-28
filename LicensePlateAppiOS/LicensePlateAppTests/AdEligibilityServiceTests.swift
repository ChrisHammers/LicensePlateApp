import Foundation
import Testing
@testable import LicensePlateApp

struct MockRemoteConfigValues: RemoteConfigValueProviding {
    var bools: [RemoteConfigService.Key: Bool] = [:]
    var ints: [RemoteConfigService.Key: Int] = [:]

    func bool(for key: RemoteConfigService.Key) -> Bool { bools[key] ?? false }
    func int(for key: RemoteConfigService.Key) -> Int { ints[key] ?? 0 }
}

@MainActor
struct AdEligibilityServiceTests {
    @Test func freeUserSeesAdsWhenEnabled() {
        let service = AdEligibilityService(
            remoteConfig: MockRemoteConfigValues(bools: [.adsEnabledFreeTier: true]),
            effectiveTierProvider: { _ in .signedUp }
        )
        let user = AppUser(id: "u1", userName: "User", firebaseUID: "u1")

        #expect(service.shouldShowAd(for: .travelLog, user: user))
    }

    @Test func premiumUserDoesNotSeeAds() {
        let service = AdEligibilityService(
            remoteConfig: MockRemoteConfigValues(bools: [.adsEnabledFreeTier: true]),
            effectiveTierProvider: { _ in .gold }
        )
        let user = AppUser(id: "u1", userName: "User", firebaseUID: "u1")

        #expect(service.shouldShowAd(for: .travelLog, user: user) == false)
    }

    @Test func remoteConfigCanDisableAds() {
        let service = AdEligibilityService(
            remoteConfig: MockRemoteConfigValues(bools: [.adsEnabledFreeTier: false]),
            effectiveTierProvider: { _ in .guest }
        )

        #expect(service.shouldShowAd(for: .travelLog, user: nil) == false)
    }
}
