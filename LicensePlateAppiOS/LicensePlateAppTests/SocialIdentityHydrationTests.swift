//
//  SocialIdentityHydrationTests.swift
//  LicensePlateAppTests
//
//  Identity displayName + family member/pending user linking for social rows.
//

import Foundation
import SwiftData
import Testing
@testable import LicensePlateApp

@MainActor
struct SocialIdentityHydrationTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [config]
        )
    }

    // F-6 rework: real names are never collected — displayName is always the username,
    // even when a legacy row still carries stored name values (frozen schema).
    @Test func cachedIdentityMapUsesUsernameAsDisplayName() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let user = AppUser(
            id: "uid-1",
            userName: "scoutotter",
            firstName: "Alex",
            lastName: "Scout",
            firebaseUID: "uid-1"
        )
        user.avatarId = "scout_otter"
        context.insert(user)
        try context.save()

        let repository = UserRepository.shared
        repository.setModelContext(context)

        let map = repository.cachedIdentityMap(forUserIds: ["uid-1"])
        #expect(map["uid-1"]?.displayName == "scoutotter")
        #expect(map["uid-1"]?.avatarId == "scout_otter")
        #expect(map["uid-1"]?.displayName != "Alex Scout")
    }

    @Test func getMembersAndPendingExposeLinkedUsers() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let familyId = "family-hydration-1"
        let memberUserId = "member-1"
        let pendingUserId = "pending-1"

        let memberUser = AppUser(
            id: memberUserId,
            userName: "captain_jane",
            firstName: "Jane",
            lastName: "Captain",
            firebaseUID: memberUserId
        )
        memberUser.avatarId = "navigator_raccoon"
        context.insert(memberUser)

        let pendingUser = AppUser(
            id: pendingUserId,
            userName: "pending_pat",
            firstName: "Pat",
            lastName: "Pending",
            firebaseUID: pendingUserId
        )
        pendingUser.avatarId = "scout_otter"
        context.insert(pendingUser)

        let member = FamilyMember(familyId: familyId, userId: memberUserId, role: .captain)
        member.user = memberUser
        context.insert(member)

        let pending = PendingJoinRequest(
            requestId: "req-1",
            familyId: familyId,
            userId: pendingUserId,
            requestedBy: pendingUserId,
            method: .code,
            status: .pending,
            user: pendingUser
        )
        context.insert(pending)
        try context.save()

        let familyRepository = FamilyRepository.shared
        familyRepository.setModelContext(context)

        let members = familyRepository.getMembers(familyId: familyId)
        #expect(members.count == 1)
        #expect(members.first?.user?.displayName == "captain_jane")
        #expect(members.first?.user?.avatarId == "navigator_raccoon")

        let pendingRequests = familyRepository.getPendingRequests(familyId: familyId)
        #expect(pendingRequests.count == 1)
        #expect(pendingRequests.first?.user?.displayName == "pending_pat")
        #expect(pendingRequests.first?.user?.avatarId == "scout_otter")
    }

    @Test func linkUserToMembersAttachesCachedUserToPendingRequest() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let familyId = "family-link-pending"
        let pendingUserId = "pending-link-1"

        let cachedUser = AppUser(
            id: pendingUserId,
            userName: "link_pat",
            firstName: "Link",
            lastName: "Pat",
            firebaseUID: pendingUserId
        )
        cachedUser.avatarId = "scout_otter"
        context.insert(cachedUser)

        let pending = PendingJoinRequest(
            requestId: "req-link-1",
            familyId: familyId,
            userId: pendingUserId,
            requestedBy: "captain-1",
            method: .search,
            status: .pending,
            user: nil
        )
        context.insert(pending)
        try context.save()

        let familyRepository = FamilyRepository.shared
        familyRepository.setModelContext(context)
        UserRepository.shared.setModelContext(context)

        #expect(familyRepository.getPendingRequests(familyId: familyId).first?.user == nil)

        // Simulate post-getUser link (cache hit path used by fetchAndCacheUsers).
        let fetched = try await UserRepository.shared.getUser(userId: pendingUserId)
        #expect(fetched?.displayName == "link_pat")
        familyRepository.linkUserToMembers(userId: pendingUserId, familyId: familyId)

        let linked = familyRepository.getPendingRequests(familyId: familyId)
        #expect(linked.count == 1)
        #expect(linked.first?.user?.displayName == "link_pat")
        #expect(linked.first?.user?.avatarId == "scout_otter")
    }
}
