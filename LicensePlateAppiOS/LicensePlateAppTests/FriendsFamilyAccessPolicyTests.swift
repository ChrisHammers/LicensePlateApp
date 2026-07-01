//
//  FriendsFamilyAccessPolicyTests.swift
//  LicensePlateAppTests
//

import Foundation
import Testing
@testable import LicensePlateApp

@MainActor
struct FriendsFamilyAccessPolicyTests {

    @Test func localGuestCannotUseFriendsAndFamily() async throws {
        let user = AppUser(id: "local", userName: "Guest")
        let policy = FriendsFamilyAccessPolicy(
            accountStateProvider: StaticAccountStateProvider(.localGuest)
        )
        #expect(policy.canUseFriendsAndFamily(for: user) == false)
    }

    @Test func firebaseAnonymousCannotUseFriendsAndFamily() async throws {
        let user = AppUser(id: "anon", userName: "Anon", firebaseUID: "anon")
        let policy = FriendsFamilyAccessPolicy(
            accountStateProvider: StaticAccountStateProvider(.firebaseAnonymous)
        )
        #expect(policy.canUseFriendsAndFamily(for: user) == false)
    }

    @Test func signedInUserCanUseFriendsAndFamily() async throws {
        let user = AppUser(id: "signed", userName: "Signed", firebaseUID: "signed")
        let policy = FriendsFamilyAccessPolicy(
            accountStateProvider: StaticAccountStateProvider(.signedIn)
        )
        #expect(policy.canUseFriendsAndFamily(for: user) == true)
    }
}
