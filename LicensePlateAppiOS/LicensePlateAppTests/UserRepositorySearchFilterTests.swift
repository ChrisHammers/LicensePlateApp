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

    // MARK: - FR-71 (F-27): child devices never transmit a search query

    /// A registered, non-guest searcher so the ONLY thing that can produce an empty
    /// result is the posture gate under test — never the pre-existing guest-like gate
    /// above, which a child-directed session would also trip and so would not isolate
    /// this FR's behavior.
    private func nonGuestRepository(posture: @escaping () -> ChildSessionPosture) -> UserRepository {
        let policy = FriendsFamilyAccessPolicy(
            accountStateProvider: StaticAccountStateProvider(.signedIn)
        )
        return UserRepository(friendsFamilyAccessPolicy: policy, posture: posture)
    }

    private let nonGuestSearcher = AppUser(id: "adult", userName: "Adult", firebaseUID: "adult")

    @Test func searchUsersReturnsEmptyForChildDirectedPosture() async throws {
        let repository = nonGuestRepository(posture: { .childDirected })

        let results = try await repository.searchUsers(
            query: "test",
            searchType: .username,
            searchingUser: nonGuestSearcher
        )

        #expect(results.isEmpty)
    }

    @Test func searchUsersReturnsEmptyForRatchetedAnonymousPosture() async throws {
        let repository = nonGuestRepository(posture: { .ratchetedAnonymous })

        let results = try await repository.searchUsers(
            query: "test",
            searchType: .username,
            searchingUser: nonGuestSearcher
        )

        #expect(results.isEmpty)
    }

    @Test func searchUsersReturnsEmptyForUnresolvedPosture() async throws {
        let repository = nonGuestRepository(posture: { .unresolved })

        let results = try await repository.searchUsers(
            query: "test",
            searchType: .username,
            searchingUser: nonGuestSearcher
        )

        #expect(results.isEmpty)
    }

    /// Guards against a regression that accidentally blocks (or inverts) the new gate
    /// for the one posture that must keep search working. `confirmedNonChild` must NOT
    /// take this function's `return []` branch — it must fall through toward the real
    /// sign-in / App Check / `searchUsers` callable path.
    ///
    /// This unit-test host has no Firebase session, so the first thing the real path
    /// hits (`FriendsFamilyAccessPolicy.validateFriendsFamilyCallableAccess`, which
    /// reads live `Auth.auth().currentUser`) throws "not signed in" rather than
    /// completing a network round-trip — there is no injectable seam around the
    /// `searchUsers` callable itself (none exists anywhere in this codebase; every
    /// other callable is exercised live-or-not-at-all the same way). Throwing here,
    /// instead of returning `[]`, is exactly the proof this gate did not fire.
    @Test func confirmedNonChildPostureProceedsPastTheSearchGate() async throws {
        let repository = nonGuestRepository(posture: { .confirmedNonChild })

        await #expect(throws: (any Error).self) {
            _ = try await repository.searchUsers(
                query: "test",
                searchType: .username,
                searchingUser: nonGuestSearcher
            )
        }
    }
}
