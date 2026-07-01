//
//  FriendsFamilyCallableGateTests.swift
//  LicensePlateAppTests
//

import Foundation
import Testing
@testable import LicensePlateApp

struct FriendsFamilyCallableGateTests {

    @Test func blocksAnonymousAccountStateFromCallableAccess() {
        #expect(
            FriendsFamilyAccessPolicy.blocksCallableAccess(
                accountState: .firebaseAnonymous,
                hasFirebaseSession: true
            )
        )
    }

    @Test func blocksLocalGuestWithoutFirebaseSession() {
        #expect(
            FriendsFamilyAccessPolicy.blocksCallableAccess(
                accountState: .localGuest,
                hasFirebaseSession: false
            )
        )
    }

    @Test func allowsSignedInAccountStateWithFirebaseSession() {
        #expect(
            !FriendsFamilyAccessPolicy.blocksCallableAccess(
                accountState: .signedIn,
                hasFirebaseSession: true
            )
        )
    }
}
