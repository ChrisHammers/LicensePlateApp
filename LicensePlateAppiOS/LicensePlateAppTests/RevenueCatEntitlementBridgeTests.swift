//
//  RevenueCatEntitlementBridgeTests.swift
//  LicensePlateAppTests
//
//  Step 09 — mock RevenueCat bridge; verify EntitlementService merges tier/tags for current user.
//

import Foundation
import SwiftData
import Testing
@testable import LicensePlateApp

// MARK: - Mock bridge (no RevenueCat SDK)

@MainActor
final class MockRevenueCatBridge: RevenueCatEntitlementProviding {
    var currentTier: UserTier
    var currentTags: Set<String>
    var offerings: [PaywallPackage]
    var isConfigured: Bool

    init(tier: UserTier = .guest, tags: Set<String> = [], offerings: [PaywallPackage] = [], isConfigured: Bool = true) {
        self.currentTier = tier
        self.currentTags = tags
        self.offerings = offerings
        self.isConfigured = isConfigured
    }

    func hasActiveEntitlement(for tier: UserTier) -> Bool {
        currentTier >= tier
    }

    func loadOfferings() async {
        // No-op for mock
    }

    func purchase(packageId: String) async -> Bool {
        false
    }

    func restore() async -> Bool {
        false
    }

    func identify(userId: String?) async {
        // No-op
    }
}

// MARK: - Tests

struct RevenueCatEntitlementBridgeTests {

    @Test @MainActor func entitlementServiceUsesBridgeTierForCurrentUser() async throws {
        let bridge = MockRevenueCatBridge(tier: .gold, tags: ["founder"])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let container = try ModelContainer(for: schema, configurations: config)
        let context = ModelContext(container)

        let user = AppUser(
            id: "user1",
            userName: "Test",
            createdAt: .now,
            lastUpdated: .now,
            avatarColor: .blue,
            avatarType: .man,
            linkedPlatforms: [],
            firebaseUID: "user1"
        )
        context.insert(user)
        try context.save()

        let familyRepo = FamilyRepository.shared
        let userRepo = UserRepository.shared
        let entitlementService = EntitlementService(familyRepository: familyRepo, userRepository: userRepo, revenueCatBridge: bridge)
        entitlementService.setModelContext(context)
        entitlementService.setCurrentUserId("user1")

        let state = entitlementService.entitlementState(for: user)

        #expect(state.userTier == .gold)
        #expect(state.hasTag("founder"))
    }

    @Test @MainActor func entitlementServiceIgnoresBridgeForNonCurrentUser() async throws {
        let bridge = MockRevenueCatBridge(tier: .royale, tags: ["lifetime"])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let container = try ModelContainer(for: schema, configurations: config)
        let context = ModelContext(container)

        let user = AppUser(
            id: "otherUser",
            userName: "Other",
            createdAt: .now,
            lastUpdated: .now,
            avatarColor: .blue,
            avatarType: .man,
            linkedPlatforms: [],
            firebaseUID: "otherUser"
        )
        context.insert(user)
        try context.save()

        let entitlementService = EntitlementService(familyRepository: .shared, userRepository: .shared, revenueCatBridge: bridge)
        entitlementService.setModelContext(context)
        entitlementService.setCurrentUserId("currentUser")

        let state = entitlementService.entitlementState(for: user)

        #expect(state.userTier == .signedUp)
        #expect(state.tags.isEmpty)
    }

    @Test @MainActor func mockBridgeHasActiveEntitlement() async throws {
        let bridge = MockRevenueCatBridge(tier: .gold)
        #expect(bridge.hasActiveEntitlement(for: .guest) == true)
        #expect(bridge.hasActiveEntitlement(for: .signedUp) == true)
        #expect(bridge.hasActiveEntitlement(for: .gold) == true)
        #expect(bridge.hasActiveEntitlement(for: .royale) == false)
    }
}
