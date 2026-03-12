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
        let vm = PaywallViewModel(bridge: bridge, analytics: .shared)
        vm.setUnlockContext(.gold)

        let title = vm.unlockReasonTitle

        #expect(title.contains("Gold") || title == "Gold member avatar".localized)
    }

    @Test @MainActor func unlockReasonMessageForRoyaleReturnsExpectedString() async throws {
        let bridge = MockRevenueCatBridge(tier: .guest)
        let vm = PaywallViewModel(bridge: bridge, analytics: .shared)
        vm.setUnlockContext(.royale)

        let message = vm.unlockReasonMessage

        #expect(message.contains("Royale") || message == "Upgrade to Royale for access to this avatar.".localized)
    }

    @Test @MainActor func canShowUpgradeTrueForPurchasableTiers() async throws {
        let bridge = MockRevenueCatBridge(tier: .guest)
        let vm = PaywallViewModel(bridge: bridge, analytics: .shared)

        vm.setUnlockContext(.signedUp)
        #expect(vm.canShowUpgrade == true)
        vm.setUnlockContext(.gold)
        #expect(vm.canShowUpgrade == true)
        vm.setUnlockContext(.royale)
        #expect(vm.canShowUpgrade == true)
    }

    @Test @MainActor func canShowUpgradeFalseForNonPurchasableTiers() async throws {
        let bridge = MockRevenueCatBridge(tier: .guest)
        let vm = PaywallViewModel(bridge: bridge, analytics: .shared)

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
        let vm = PaywallViewModel(bridge: bridge, analytics: .shared)

        await vm.loadOfferings(source: "test")

        #expect(vm.packages.count == 1)
        #expect(vm.packages[0].id == "monthly")
        #expect(vm.packages[0].displayName == "Monthly")
    }
}
