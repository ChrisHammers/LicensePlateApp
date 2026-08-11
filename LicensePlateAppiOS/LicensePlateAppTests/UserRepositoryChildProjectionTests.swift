//
//  UserRepositoryChildProjectionTests.swift
//  LicensePlateAppTests
//
//  COPPA F-7 (SRS §7.1): the in-memory isChildAccount projection — ingest,
//  tri-state accessor (nil never treated as adult), sign-out clear, parsing.
//

import Foundation
import Testing
@testable import LicensePlateApp

@MainActor
struct UserRepositoryChildProjectionTests {

    @Test func parseTreatsMissingFlagOnExistingDocAsNotChild() {
        // §4: on an EXISTING doc, missing flag ⇒ not a child.
        #expect(UserRepository.parseIsChildAccount(from: ["userName": "kid"]) == false)
        #expect(UserRepository.parseIsChildAccount(from: ["isChildAccount": true]) == true)
        #expect(UserRepository.parseIsChildAccount(from: ["isChildAccount": false]) == false)
    }

    @Test func projectionIsTriStateAndNilUntilIngest() {
        let repo = UserRepository()
        let uid = "projection-test-\(UUID().uuidString)"

        // nil = unresolved; consumers must never read this as "not child".
        #expect(repo.isChildAccount(for: uid) == nil)

        repo.ingestIsChildAccount(userId: uid, isChild: true)
        #expect(repo.isChildAccount(for: uid) == true)

        repo.ingestIsChildAccount(userId: uid, isChild: false)
        #expect(repo.isChildAccount(for: uid) == false)
    }

    @Test func signOutClearsTheProjection() {
        let repo = UserRepository()
        let uid = "projection-clear-\(UUID().uuidString)"
        repo.ingestIsChildAccount(userId: uid, isChild: true)
        #expect(repo.isChildAccount(for: uid) == true)

        repo.clearInMemoryState()
        #expect(repo.isChildAccount(for: uid) == nil)
    }

    @Test func emptyUserIdIsIgnored() {
        let repo = UserRepository()
        repo.ingestIsChildAccount(userId: "", isChild: true)
        #expect(repo.isChildAccount(for: "") == nil)
    }
}
