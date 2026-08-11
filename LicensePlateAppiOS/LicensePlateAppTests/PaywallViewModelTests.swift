//
//  PaywallViewModelTests.swift
//  LicensePlateAppTests
//
//  Step 09 — PaywallViewModel with mock bridge; unlock-context messaging and state.
//

import Foundation
import Testing
@testable import LicensePlateApp

// MARK: - Tests

struct PaywallViewModelTests {

    @Test @MainActor func unlockReasonTitleForGoldReturnsExpectedString() async throws {
        let bridge = MockRevenueCatBridge(tier: .guest)
        let spy = AnalyticsLoggingSpy()
        let vm = PaywallViewModel(bridge: bridge, analytics: spy)
        vm.setUnlockContext(.gold)

        let title = vm.unlockReasonTitle

        #expect(title.contains("Gold") || title == "Gold member avatar".localized)
    }

    @Test @MainActor func unlockReasonMessageForRoyaleReturnsExpectedString() async throws {
        let bridge = MockRevenueCatBridge(tier: .guest)
        let spy = AnalyticsLoggingSpy()
        let vm = PaywallViewModel(bridge: bridge, analytics: spy)
        vm.setUnlockContext(.royale)

        let message = vm.unlockReasonMessage

        #expect(message.contains("Royale") || message == "Upgrade to Royale for access to this avatar.".localized)
    }

    @Test @MainActor func canShowUpgradeTrueForPurchasableTiers() async throws {
        let bridge = MockRevenueCatBridge(tier: .guest)
        let spy = AnalyticsLoggingSpy()
        let vm = PaywallViewModel(bridge: bridge, analytics: spy)

        vm.setUnlockContext(.signedUp)
        #expect(vm.canShowUpgrade == true)
        vm.setUnlockContext(.gold)
        #expect(vm.canShowUpgrade == true)
        vm.setUnlockContext(.royale)
        #expect(vm.canShowUpgrade == true)
    }

    @Test @MainActor func canShowUpgradeFalseForNonPurchasableTiers() async throws {
        let bridge = MockRevenueCatBridge(tier: .guest)
        let spy = AnalyticsLoggingSpy()
        let vm = PaywallViewModel(bridge: bridge, analytics: spy)

        vm.setUnlockContext(.founder)
        #expect(vm.canShowUpgrade == false)
        vm.setUnlockContext(.familyPass)
        #expect(vm.canShowUpgrade == false)
    }

    @Test @MainActor func loadOfferingsUpdatesPackagesFromBridge() async throws {
        let packages = [
            PaywallPackage(id: "monthly", displayName: "Monthly", displayPrice: "$4.99", packageType: "monthly")
        ]
        let bridge = MockRevenueCatBridge(offerings: packages)
        let spy = AnalyticsLoggingSpy()
        let vm = PaywallViewModel(bridge: bridge, analytics: spy)

        await vm.loadOfferings(source: "test")

        #expect(vm.packages.count == 1)
        #expect(vm.packages[0].id == "monthly")
        #expect(vm.packages[0].displayName == "Monthly")
        #expect(spy.loggedEvents.contains { $0.name == "paywall_viewed" })
        #expect(spy.loggedEvents.first { $0.name == "paywall_viewed" }?.parameters?["source"] as? String == "test")
    }

    @Test @MainActor func savedTripContextUsesAnonymousSignUpCopy() async throws {
        let vm = PaywallViewModel(bridge: MockRevenueCatBridge(tier: .guest), analytics: AnalyticsLoggingSpy())

        vm.setSavedTripLimitContext(isAnonymous: true)

        #expect(vm.unlockReasonTitle == "Sign up to keep more saved trips".localized)
    }

    // MARK: - COPPA F-7 (FR-34): child sessions never initiate purchases

    @Test @MainActor func purchaseIsRefusedWhileSuppressedForChildSession() async throws {
        let spy = AnalyticsLoggingSpy()
        let vm = PaywallViewModel(
            bridge: MockRevenueCatBridge(tier: .guest),
            analytics: spy,
            purchasesSuppressed: { true }
        )

        await vm.purchase(packageId: "monthly")

        // Short-circuits before any purchase flow or analytics event.
        #expect(spy.loggedEvents.isEmpty)
        #expect(vm.errorMessage == nil)
        #expect(vm.isPurchasing == false)
    }

    @Test @MainActor func purchaseProceedsWhenNotSuppressed() async throws {
        let spy = AnalyticsLoggingSpy()
        let vm = PaywallViewModel(
            bridge: MockRevenueCatBridge(tier: .guest),
            analytics: spy,
            purchasesSuppressed: { false }
        )

        await vm.purchase(packageId: "monthly")

        #expect(spy.loggedEvents.contains { $0.name == "purchase_started" })
    }
}
