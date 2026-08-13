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

    /// The provenance split (GAP 1(b)): both an explicit `false` and an ABSENT key
    /// resolve to `isChild == false` for gating — a legitimate adult document never
    /// carries the key, so treating absence as unresolved would hold every adult
    /// forever. Only `isServerExplicit` tells them apart.
    @Test func resolutionSeparatesExplicitFalseFromAnAbsentFlag() {
        let absent = UserRepository.parseChildAccountResolution(from: ["userName": "kid"])
        #expect(absent.isChild == false)
        #expect(absent.isServerExplicit == false)

        let explicitFalse = UserRepository.parseChildAccountResolution(from: ["isChildAccount": false])
        #expect(explicitFalse.isChild == false)
        #expect(explicitFalse.isServerExplicit == true)

        let explicitTrue = UserRepository.parseChildAccountResolution(from: ["isChildAccount": true])
        #expect(explicitTrue.isChild == true)
        #expect(explicitTrue.isServerExplicit == true)
    }

    @Test func projectionIsTriStateAndNilUntilIngest() {
        let repo = UserRepository()
        let uid = "projection-test-\(UUID().uuidString)"

        // nil = unresolved; consumers must never read this as "not child".
        #expect(repo.isChildAccount(for: uid) == nil)
        #expect(repo.isChildAccountFlagExplicit(for: uid) == false)

        repo.ingestChildAccountResolution(
            userId: uid,
            .init(isChild: true, isServerExplicit: true)
        )
        #expect(repo.isChildAccount(for: uid) == true)
        #expect(repo.isChildAccountFlagExplicit(for: uid) == true)

        repo.ingestChildAccountResolution(
            userId: uid,
            .init(isChild: false, isServerExplicit: true)
        )
        #expect(repo.isChildAccount(for: uid) == false)
        #expect(repo.isChildAccountFlagExplicit(for: uid) == true)
    }

    /// A resolved-but-flagless doc gates as not-a-child yet is never "explicit", so it
    /// can never authorize the destructive correction path.
    @Test func anAbsentFlagResolvesAsNotChildButNeverAsExplicit() {
        let repo = UserRepository()
        let uid = "projection-absent-\(UUID().uuidString)"

        repo.ingestChildAccountResolution(
            userId: uid,
            UserRepository.parseChildAccountResolution(from: ["userName": "kid"])
        )
        #expect(repo.isChildAccount(for: uid) == false)
        #expect(repo.isChildAccountFlagExplicit(for: uid) == false)
    }

    @Test func signOutClearsTheProjection() {
        let repo = UserRepository()
        let uid = "projection-clear-\(UUID().uuidString)"
        repo.ingestChildAccountResolution(
            userId: uid,
            .init(isChild: true, isServerExplicit: true)
        )
        #expect(repo.isChildAccount(for: uid) == true)

        repo.clearInMemoryState()
        #expect(repo.isChildAccount(for: uid) == nil)
        #expect(repo.isChildAccountFlagExplicit(for: uid) == false)
    }

    @Test func emptyUserIdIsIgnored() {
        let repo = UserRepository()
        repo.ingestChildAccountResolution(
            userId: "",
            .init(isChild: true, isServerExplicit: true)
        )
        #expect(repo.isChildAccount(for: "") == nil)
    }
}
