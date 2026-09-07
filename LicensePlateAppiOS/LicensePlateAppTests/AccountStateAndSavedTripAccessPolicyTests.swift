//
//  AccountStateAndSavedTripAccessPolicyTests.swift
//  LicensePlateAppTests
//
//  Step 17.1 — account-state driven entitlement and saved-trip UI caps.
//

import Foundation
import Testing
@testable import LicensePlateApp

@MainActor
final class StaticAccountStateProvider: AccountStateProviding {
    var state: AccountState

    init(_ state: AccountState) {
        self.state = state
    }

    func currentAccountState(for user: AppUser?) -> AccountState {
        state
    }
}

@MainActor
struct AccountStateAndSavedTripAccessPolicyTests {

    @Test func firebaseAnonymousCurrentUserResolvesBaseTierAsGuest() async throws {
        let user = AppUser(id: "anon", userName: "Anon", firebaseUID: "anon")
        let entitlementService = EntitlementService(
            revenueCatBridge: MockRevenueCatBridge(tier: .guest),
            accountStateProvider: StaticAccountStateProvider(.firebaseAnonymous)
        )
        entitlementService.setCurrentUserId("anon")

        let state = entitlementService.entitlementState(for: user)

        #expect(state.userTier == .guest)
    }

    @Test func signedInCurrentUserResolvesBaseTierAsSignedUp() async throws {
        let user = AppUser(id: "signed", userName: "Signed", firebaseUID: "signed")
        let entitlementService = EntitlementService(
            revenueCatBridge: MockRevenueCatBridge(tier: .guest),
            accountStateProvider: StaticAccountStateProvider(.signedIn)
        )
        entitlementService.setCurrentUserId("signed")

        let state = entitlementService.entitlementState(for: user)

        #expect(state.userTier == .signedUp)
    }

    @Test func revenueCatTierStillElevatesFirebaseAnonymousUser() async throws {
        let user = AppUser(id: "anon-premium", userName: "Anon Premium", firebaseUID: "anon-premium")
        let entitlementService = EntitlementService(
            revenueCatBridge: MockRevenueCatBridge(tier: .gold),
            accountStateProvider: StaticAccountStateProvider(.firebaseAnonymous)
        )
        entitlementService.setCurrentUserId("anon-premium")

        let state = entitlementService.entitlementState(for: user)

        #expect(state.userTier == .gold)
    }

    @Test func savedTripAccessPolicyCapsAnonymousSignedUpAndPremiumUsers() async throws {
        let user = AppUser(id: "user", userName: "User", firebaseUID: "user")

        let anonymousEntitlement = EntitlementService(
            revenueCatBridge: MockRevenueCatBridge(tier: .guest),
            accountStateProvider: StaticAccountStateProvider(.firebaseAnonymous)
        )
        anonymousEntitlement.setCurrentUserId("user")
        #expect(SavedTripAccessPolicy(
            entitlementService: anonymousEntitlement,
            accountStateProvider: StaticAccountStateProvider(.firebaseAnonymous)
        ).visibleSavedTripLimit(for: user) == 3)

        let signedInEntitlement = EntitlementService(
            revenueCatBridge: MockRevenueCatBridge(tier: .guest),
            accountStateProvider: StaticAccountStateProvider(.signedIn)
        )
        signedInEntitlement.setCurrentUserId("user")
        #expect(SavedTripAccessPolicy(
            entitlementService: signedInEntitlement,
            accountStateProvider: StaticAccountStateProvider(.signedIn)
        ).visibleSavedTripLimit(for: user) == 5)

        let premiumEntitlement = EntitlementService(
            revenueCatBridge: MockRevenueCatBridge(tier: .gold),
            accountStateProvider: StaticAccountStateProvider(.signedIn)
        )
        premiumEntitlement.setCurrentUserId("user")
        #expect(SavedTripAccessPolicy(
            entitlementService: premiumEntitlement,
            accountStateProvider: StaticAccountStateProvider(.signedIn)
        ).visibleSavedTripLimit(for: user) == nil)
    }

    @Test func shouldReportAuthSuccessWhenGuestLikeUpgradesToSignedIn() {
        #expect(AccountState.shouldReportAuthSuccess(from: .localGuest, to: .signedIn))
        #expect(AccountState.shouldReportAuthSuccess(from: .firebaseAnonymous, to: .signedIn))
    }

    @Test func shouldNotReportAuthSuccessWhenAlreadySignedInOrStillGuestLike() {
        #expect(!AccountState.shouldReportAuthSuccess(from: .signedIn, to: .signedIn))
        #expect(!AccountState.shouldReportAuthSuccess(from: .localGuest, to: .localGuest))
        #expect(!AccountState.shouldReportAuthSuccess(from: .firebaseAnonymous, to: .firebaseAnonymous))
        #expect(!AccountState.shouldReportAuthSuccess(from: .signedIn, to: .firebaseAnonymous))
        #expect(!AccountState.shouldReportAuthSuccess(from: .localGuest, to: .firebaseAnonymous))
    }

    @Test func guestContinuationDoesNotCreateFreshSessionWhenAlreadyGuestLike() {
        #expect(!GuestContinuationPolicy.shouldCreateFreshAnonymousSession(accountState: .localGuest))
        #expect(!GuestContinuationPolicy.shouldCreateFreshAnonymousSession(accountState: .firebaseAnonymous))
    }

    @Test func guestContinuationCreatesFreshSessionOnlyWhenSignedIn() {
        #expect(GuestContinuationPolicy.shouldCreateFreshAnonymousSession(accountState: .signedIn))
    }

    // F-35(c): the locked saved-trips row's message variant. The child check must win
    // over the anonymous check — a `.ratchetedAnonymous` session is both at once.
    @Test func childGateWinsEvenWhenAlsoAnonymous() {
        #expect(
            SavedTripLimitMessagePolicy.variant(
                purchasesSuppressed: true, isAnonymous: true, hiddenCount: 4
            ) == .childGate
        )
        #expect(
            SavedTripLimitMessagePolicy.variant(
                purchasesSuppressed: true, isAnonymous: false, hiddenCount: 4
            ) == .childGate
        )
    }

    @Test func anonymousAdultGetsSignUpUpsell() {
        #expect(
            SavedTripLimitMessagePolicy.variant(
                purchasesSuppressed: false, isAnonymous: true, hiddenCount: 2
            ) == .signUpUpsell(hiddenCount: 2)
        )
    }

    @Test func registeredAdultGetsUpgradeUpsell() {
        #expect(
            SavedTripLimitMessagePolicy.variant(
                purchasesSuppressed: false, isAnonymous: false, hiddenCount: 7
            ) == .upgradeUpsell(hiddenCount: 7)
        )
    }
}
