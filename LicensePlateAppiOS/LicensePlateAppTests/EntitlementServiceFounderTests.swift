//
//  EntitlementServiceFounderTests.swift
//  LicensePlateAppTests
//

import Foundation
import SwiftData
import Testing
@testable import LicensePlateApp

struct EntitlementServiceFounderTests {

    @Test @MainActor func firestoreFounderTagUnlocksFounderEntitlement() async throws {
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

        let userRepo = UserRepository.shared
        userRepo.ingestEntitlementTags(userId: "user1", tags: ["founder"])

        let bridge = MockRevenueCatBridge(tier: .gold, tags: ["founder", "lifetime"])
        let entitlementService = EntitlementService(
            familyRepository: .shared,
            userRepository: userRepo,
            revenueCatBridge: bridge
        )
        entitlementService.setModelContext(context)
        entitlementService.setCurrentUserId("user1")

        let state = entitlementService.entitlementState(for: user)

        #expect(state.hasTag("founder"))
        #expect(state.hasTag("lifetime"))
    }

    @Test @MainActor func revenueCatFounderTagIsIgnored() async throws {
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

        let bridge = MockRevenueCatBridge(tier: .gold, tags: ["founder"])
        let entitlementService = EntitlementService(
            familyRepository: .shared,
            userRepository: UserRepository.shared,
            revenueCatBridge: bridge
        )
        entitlementService.setModelContext(context)
        entitlementService.setCurrentUserId("user1")

        let state = entitlementService.entitlementState(for: user)

        #expect(state.hasTag("founder") == false)
    }

    @Test @MainActor func peerUserReadsFirestoreFounderTag() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let container = try ModelContainer(for: schema, configurations: config)
        let context = ModelContext(container)

        let peer = AppUser(
            id: "peerUser",
            userName: "Peer",
            createdAt: .now,
            lastUpdated: .now,
            avatarColor: .blue,
            avatarType: .man,
            linkedPlatforms: [],
            firebaseUID: "peerUser"
        )
        context.insert(peer)
        try context.save()

        let userRepo = UserRepository.shared
        userRepo.ingestEntitlementTags(userId: "peerUser", tags: ["founder"])

        let bridge = MockRevenueCatBridge(tier: .royale, tags: ["lifetime"])
        let entitlementService = EntitlementService(
            familyRepository: .shared,
            userRepository: userRepo,
            revenueCatBridge: bridge
        )
        entitlementService.setModelContext(context)
        entitlementService.setCurrentUserId("currentUser")

        let state = entitlementService.entitlementState(for: peer)

        #expect(state.hasTag("founder"))
        #expect(state.hasTag("lifetime") == false)
    }
}
