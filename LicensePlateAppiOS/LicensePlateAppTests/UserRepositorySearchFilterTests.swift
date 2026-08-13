//
//  UserRepositorySearchFilterTests.swift
//  LicensePlateAppTests
//

import Foundation
import Testing
@testable import LicensePlateApp

@MainActor
struct UserRepositorySearchFilterTests {

    @Test func searchUsersReturnsEmptyForGuestLikeSearcher() async throws {
        let policy = FriendsFamilyAccessPolicy(
            accountStateProvider: StaticAccountStateProvider(.firebaseAnonymous)
        )
        let repository = UserRepository(friendsFamilyAccessPolicy: policy)
        let guest = AppUser(id: "anon", userName: "Anon", firebaseUID: "anon")

        let results = try await repository.searchUsers(
            query: "test",
            searchType: .username,
            searchingUser: guest
        )

        #expect(results.isEmpty)
    }
}
