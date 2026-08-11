import Foundation
import Testing
@testable import LicensePlateApp

struct MockRemoteConfigValues: RemoteConfigValueProviding {
    var bools: [RemoteConfigService.Key: Bool] = [:]
    var ints: [RemoteConfigService.Key: Int] = [:]
    var strings: [RemoteConfigService.Key: String] = [:]

    func bool(for key: RemoteConfigService.Key) -> Bool { bools[key] ?? false }
    func int(for key: RemoteConfigService.Key) -> Int { ints[key] ?? 0 }
    func string(for key: RemoteConfigService.Key) -> String { strings[key] ?? "" }
}

@MainActor
struct AdEligibilityServiceTests {

    private func makeService(
        adsEnabled: Bool = true,
        tier: UserTier = .signedUp,
        posture: ChildSessionPosture = .confirmedNonChild
    ) -> AdEligibilityService {
        AdEligibilityService(
            remoteConfig: MockRemoteConfigValues(bools: [.adsEnabledFreeTier: adsEnabled]),
            effectiveTierProvider: { _ in tier },
            childPostureProvider: { posture }
        )
    }

    @Test func freeUserSeesAdsWhenEnabledAndFreshConfirmedNonChild() {
        let user = AppUser(id: "u1", userName: "User", firebaseUID: "u1")
        #expect(makeService().shouldShowAd(for: .travelLog, user: user))
    }

    @Test func premiumUserDoesNotSeeAds() {
        let user = AppUser(id: "u1", userName: "User", firebaseUID: "u1")
        #expect(makeService(tier: .gold).shouldShowAd(for: .travelLog, user: user) == false)
    }

    @Test func remoteConfigCanDisableAds() {
        #expect(makeService(adsEnabled: false, tier: .guest).shouldShowAd(for: .travelLog, user: nil) == false)
    }

    // MARK: - COPPA FR-19 (amended): fail-closed posture hold

    @Test func childSessionIsIneligibleOnEverySurface() {
        let user = AppUser(id: "c1", userName: "Child", firebaseUID: "c1")
        let service = makeService(tier: .guest, posture: .childDirected)
        for surface in AdSurface.allCases {
            #expect(service.shouldShowAd(for: surface, user: user) == false)
        }
    }

    @Test func ratchetedAnonymousSessionIsIneligible() {
        #expect(makeService(posture: .ratchetedAnonymous).shouldShowAd(for: .tripSetup, user: nil) == false)
    }

    @Test func unresolvedSessionIsIneligible() {
        // Closes the old nil-user-eligible hole: no fresh confirmation, no ads.
        let user = AppUser(id: "u1", userName: "User", firebaseUID: "u1")
        let service = makeService(posture: .unresolved)
        #expect(service.shouldShowAd(for: .travelLog, user: user) == false)
        #expect(service.shouldShowAd(for: .travelLog, user: nil) == false)
    }

    @Test func onlyFreshConfirmedNonChildSessionsSeeAds() {
        let user = AppUser(id: "u1", userName: "User", firebaseUID: "u1")
        for posture in [ChildSessionPosture.childDirected, .ratchetedAnonymous, .unresolved] {
            #expect(makeService(posture: posture).shouldShowAd(for: .tripSummary, user: user) == false)
        }
        #expect(makeService(posture: .confirmedNonChild).shouldShowAd(for: .tripSummary, user: user) == true)
    }

    @Test func familyElevatedTierStillRespectedUnderConfirmedPosture() {
        // A family-pass-elevated (gold-effective) user stays ad-free — the posture
        // gate never weakens the premium exemption.
        let user = AppUser(id: "u1", userName: "User", firebaseUID: "u1")
        #expect(makeService(tier: .gold, posture: .confirmedNonChild).shouldShowAd(for: .travelLog, user: user) == false)
    }
}
