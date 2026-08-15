//
//  RegisteredSignupIdentityContinuityTests.swift
//  LicensePlateAppTests
//
//  Owner device pass 2026-08-15, bugs 1 & 2 — "the app created the Anon user once I selected
//  my age, then created a NEW user once I signed up, instead of converting", followed by
//  "MAJOR breakage: no trip sessions written to cloud for my registered adult; airplane-mode
//  relaunch lost active trips locally; could create a second trip over the limit; anon
//  kids/adults kept theirs".
//
//  The two are one defect seen from two ends. v2.1 §11.4 makes registration a LINK, so the
//  uid survives and nothing has to move. Every path that ends on a DIFFERENT uid — the
//  fresh-account fallback after a failed link, and registering from a session that never held
//  an anonymous uid — leaves every local gameplay row naming the previous play identity.
//  Before FR-60 that was invisible: a guest's local id was a UUID for milliseconds. Under the
//  local-first model it can be days of trips, and the app resolves ownership as
//  `firebaseUID ?? id` everywhere:
//
//    * `TripSessionRepository.loadActiveSessions(userId:)` filters on
//      `createdBy == uid || participants.contains(uid)` — the trips silently stop existing;
//    * `TripEntitlementGate.activeTripCount(userId:)` counts that same filtered list — the
//      active-trip limit resets to zero used;
//    * `publishTripCanonicalState` sends `session.createdBy`, and the server's
//      `ensureOwnerMemberIfCreatorPayload` refuses to seed `members/{uid}` when it is not the
//      caller, so `assertTripOwner` rejects the publish — nothing reaches the cloud.
//
//  These tests assert the broken state as well as the fixed one, so a regression fails loudly
//  rather than quietly returning an empty list.
//

import Foundation
import SwiftData
import Testing
@testable import LicensePlateApp

// MARK: - Bug 1: which failures may fork the identity

@MainActor
struct AnonymousUpgradePolicyTests {

    /// Only a conflict over the credential itself is something a DIFFERENT account could
    /// resolve. Everything else is transient, and forking the identity in response to it
    /// costs the player their history for no gain.
    @Test func onlyACredentialConflictMayFallBackToAFreshAccount() {
        // emailAlreadyInUse / providerAlreadyLinked / credentialAlreadyInUse
        #expect(AnonymousUpgradePolicy.shouldFallBackToFreshAccount(linkErrorCode: 17007) == true)
        #expect(AnonymousUpgradePolicy.shouldFallBackToFreshAccount(linkErrorCode: 17015) == true)
        #expect(AnonymousUpgradePolicy.shouldFallBackToFreshAccount(linkErrorCode: 17025) == true)

        // networkError, userTokenExpired, tooManyRequests, internalError, weakPassword —
        // the anonymous session is still good and the user can simply retry.
        #expect(AnonymousUpgradePolicy.shouldFallBackToFreshAccount(linkErrorCode: 17020) == false)
        #expect(AnonymousUpgradePolicy.shouldFallBackToFreshAccount(linkErrorCode: 17017) == false)
        #expect(AnonymousUpgradePolicy.shouldFallBackToFreshAccount(linkErrorCode: 17010) == false)
        #expect(AnonymousUpgradePolicy.shouldFallBackToFreshAccount(linkErrorCode: 17999) == false)
        #expect(AnonymousUpgradePolicy.shouldFallBackToFreshAccount(linkErrorCode: 17026) == false)
    }

    /// The regression that produced bug 1: a Firestore failure raised AFTER a successful link
    /// used to land in the same `catch` as a link failure, and answer it by signing the linked
    /// session out and registering a second account. A post-link failure has no error code in
    /// this set, so it can no longer reach the fallback.
    @Test func firestorePermissionAndUnavailableCodesAreNotLinkFallbacks() {
        // Firestore's NSError codes (7 = permission-denied, 14 = unavailable) share the
        // numeric space with nothing in the fallback set.
        #expect(AnonymousUpgradePolicy.shouldFallBackToFreshAccount(linkErrorCode: 7) == false)
        #expect(AnonymousUpgradePolicy.shouldFallBackToFreshAccount(linkErrorCode: 14) == false)
    }

    /// A link keeps the uid, so there is nothing to carry. Every other outcome has to move the
    /// local play history explicitly — `signInAnonymously` is not on those paths, so FR-60(d)'s
    /// rebind does not run by itself.
    @Test func onlyAChangedUidRequiresCarryingTheLocalPlayHistory() {
        #expect(AnonymousUpgradePolicy.requiresLocalPlayIdentityRebind(
            previousPlayIdentity: "anon-uid", registeredUid: "anon-uid"
        ) == false)
        #expect(AnonymousUpgradePolicy.requiresLocalPlayIdentityRebind(
            previousPlayIdentity: "anon-uid", registeredUid: "registered-uid"
        ) == true)
        #expect(AnonymousUpgradePolicy.requiresLocalPlayIdentityRebind(
            previousPlayIdentity: "3F2E1D00-0000-0000-0000-00000000AAAA", registeredUid: "registered-uid"
        ) == true)
        #expect(AnonymousUpgradePolicy.requiresLocalPlayIdentityRebind(
            previousPlayIdentity: nil, registeredUid: "registered-uid"
        ) == false)
        // Rebinding onto an empty uid would erase ownership rather than move it.
        #expect(AnonymousUpgradePolicy.requiresLocalPlayIdentityRebind(
            previousPlayIdentity: "anon-uid", registeredUid: ""
        ) == false)
    }
}

// MARK: - Bug 2: the consequences, against real SwiftData

@MainActor
struct RegisteredSignupTripContinuityTests {

    private let anonUid = "anon-uid-before-signup"
    private let registeredUid = "registered-uid-after-signup"

    private func makeContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [config]
        )
        let context = ModelContext(container)
        TripSessionRepository.shared.setModelContext(context)
        LocalPlayIdentityRepository.shared.setModelContext(context)
        XpLedgerRepository.shared.setModelContext(context)
        return context
    }

    /// A trip the player created while still an anonymous guest, exactly as the owner had
    /// before they signed up.
    @discardableResult
    private func seedActiveTripOwnedByAnon(id: UUID = UUID()) throws -> TripSession {
        let created = Date()
        let session = TripSession(
            id: id,
            name: "Road trip",
            status: .active,
            createdAt: created,
            createdBy: anonUid,
            startedAt: created,
            endedAt: nil,
            endedBy: nil,
            participants: [TripParticipant(userId: anonUid, role: .owner, joinedAt: created)]
        )
        try TripSessionRepository.shared.create(session: session)
        return session
    }

    /// (a) Registered signup after anonymous play keeps the trips locally.
    @Test func signupAfterAnonymousPlayKeepsTheTripsLocally() throws {
        _ = try makeContext()
        try seedActiveTripOwnedByAnon()

        // THE BUG: registering onto a new uid without carrying the history. The trip is
        // still on disk and still completely invisible.
        #expect(try TripSessionRepository.shared.loadActiveSessions(userId: anonUid).count == 1)
        #expect(try TripSessionRepository.shared.loadActiveSessions(userId: registeredUid).isEmpty)

        // THE FIX: the registration path carries the play identity across.
        let summary = try LocalPlayIdentityRepository.shared.rebindLocalPlayIdentity(
            from: anonUid, to: registeredUid
        )
        #expect(summary.tripSessions == 1)

        let visible = try TripSessionRepository.shared.loadActiveSessions(userId: registeredUid)
        #expect(visible.count == 1)
        #expect(visible[0].createdBy == registeredUid)
        // The roster moved with it, so `isTripCreator` and participant lookups still resolve.
        #expect(visible[0].participants.map(\.userId) == [registeredUid])
    }

    /// (b) The active-trip limit survives the upgrade. Before the fix the registered user's
    /// count read zero, so a guest-tier player could hold two concurrent trips.
    @Test func theActiveTripLimitSurvivesTheUpgrade() throws {
        _ = try makeContext()
        try seedActiveTripOwnedByAnon()

        let gate = TripEntitlementGate(
            tripSessionRepository: TripSessionRepository.shared,
            entitlementService: EntitlementService(),
            analytics: AnalyticsLoggingSpy()
        )

        // THE BUG: one active trip on disk, zero counted for the new identity, limit reset.
        #expect(try gate.activeTripCount(userId: registeredUid) == 0)
        #expect(throws: Never.self) {
            try gate.validateCanAddActiveTrip(user: nil, userId: registeredUid, source: .create)
        }

        try LocalPlayIdentityRepository.shared.rebindLocalPlayIdentity(
            from: anonUid, to: registeredUid
        )

        // THE FIX: the trip counts against the same player it always did.
        #expect(try gate.activeTripCount(userId: registeredUid) == 1)
        #expect(throws: TripEntitlementGateError.self) {
            try gate.validateCanAddActiveTrip(user: nil, userId: registeredUid, source: .create)
        }
    }

    /// (b, second half) The offline relaunch. `loadActiveSessions` is the only thing standing
    /// between a killed app and the player's trips, and it is purely local — so once the rows
    /// name the registered uid, an airplane-mode relaunch resolves them with no network at all.
    @Test func anOfflineRelaunchAsTheRegisteredAdultStillSeesTheTrips() throws {
        let context = try makeContext()
        try seedActiveTripOwnedByAnon()
        try LocalPlayIdentityRepository.shared.rebindLocalPlayIdentity(
            from: anonUid, to: registeredUid
        )

        // Relaunch: a brand-new repository instance over the same store, nothing cached.
        let relaunched = ModelContext(context.container)
        TripSessionRepository.shared.setModelContext(relaunched)

        let visible = try TripSessionRepository.shared.loadActiveSessions(userId: registeredUid)
        #expect(visible.count == 1)
        #expect(visible[0].status == .active)
    }

    /// (c) The publish path's precondition, stated locally. The server refuses a payload whose
    /// `createdBy` is not the caller (`ensureOwnerMemberIfCreatorPayload` declines to seed the
    /// owner row, `assertTripOwner` then rejects) — pinned server-side in
    /// `functions/src/tripSessionOwnershipHardening.test.ts`. The client's half of that
    /// contract is simply that the row it publishes names the account it publishes as.
    @Test func thePublishedSessionNamesTheAccountThatPublishesIt() throws {
        _ = try makeContext()
        try seedActiveTripOwnedByAnon()

        let beforeFix = try #require(
            try TripSessionRepository.shared.loadActiveSessions(userId: anonUid).first
        )
        #expect(beforeFix.createdBy != registeredUid) // the refused publish

        try LocalPlayIdentityRepository.shared.rebindLocalPlayIdentity(
            from: anonUid, to: registeredUid
        )

        let afterFix = try #require(
            try TripSessionRepository.shared.loadActiveSessions(userId: registeredUid).first
        )
        #expect(afterFix.createdBy == registeredUid)
    }

    /// A linked upgrade is the normal path and must stay a genuine no-op: the uid does not
    /// change, so nothing is rewritten and no row is touched twice.
    @Test func aLinkedUpgradeMovesNothingBecauseTheUidNeverChanged() throws {
        _ = try makeContext()
        try seedActiveTripOwnedByAnon()

        #expect(AnonymousUpgradePolicy.requiresLocalPlayIdentityRebind(
            previousPlayIdentity: anonUid, registeredUid: anonUid
        ) == false)
        let summary = try LocalPlayIdentityRepository.shared.rebindLocalPlayIdentity(
            from: anonUid, to: anonUid
        )
        #expect(summary == .none)
        #expect(try TripSessionRepository.shared.loadActiveSessions(userId: anonUid).count == 1)
    }

    /// A co-participant on a shared trip is never swept up: the rewrite is scoped by equality
    /// with the one identity being retired.
    @Test func aCoParticipantIsNeverRewritten() throws {
        _ = try makeContext()
        let created = Date()
        let session = TripSession(
            id: UUID(),
            name: "Shared trip",
            status: .active,
            createdAt: created,
            createdBy: anonUid,
            startedAt: created,
            endedAt: nil,
            endedBy: nil,
            participants: [
                TripParticipant(userId: anonUid, role: .owner, joinedAt: created),
                TripParticipant(userId: "sibling-uid", role: .member, joinedAt: created)
            ]
        )
        try TripSessionRepository.shared.create(session: session)

        try LocalPlayIdentityRepository.shared.rebindLocalPlayIdentity(
            from: anonUid, to: registeredUid
        )

        let moved = try #require(
            try TripSessionRepository.shared.loadActiveSessions(userId: registeredUid).first
        )
        #expect(Set(moved.participants.map(\.userId)) == [registeredUid, "sibling-uid"])
        // The sibling still sees the trip they are on.
        #expect(try TripSessionRepository.shared.loadActiveSessions(userId: "sibling-uid").count == 1)
    }
}
