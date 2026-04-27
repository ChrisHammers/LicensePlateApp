//
//  TripEntitlementGateTests.swift
//  LicensePlateAppTests
//
//  Step 17 — Active-trip entitlement gates.
//

import Foundation
import Testing
@testable import LicensePlateApp

@MainActor
struct TripEntitlementGateTests {
    private func makeUser(id: String = "user1", firebaseUID: String? = "user1") -> AppUser {
        AppUser(id: id, userName: "User", firebaseUID: firebaseUID)
    }

    @Test func activeTripLimitsByTier() throws {
        let gate = TripEntitlementGate(
            tripSessionRepository: MockTripSessionRepository(),
            entitlementService: EntitlementService(),
            analytics: AnalyticsLoggingSpy()
        )

        #expect(gate.activeTripLimit(for: EntitlementState(userTier: .guest, familyId: nil, wasEverInFamily: false, familyRole: nil, tags: [], creatorTierForFamily: nil)) == 1)
        #expect(gate.activeTripLimit(for: EntitlementState(userTier: .signedUp, familyId: nil, wasEverInFamily: false, familyRole: nil, tags: [], creatorTierForFamily: nil)) == 1)
        #expect(gate.activeTripLimit(for: EntitlementState(userTier: .gold, familyId: nil, wasEverInFamily: false, familyRole: nil, tags: [], creatorTierForFamily: nil)) == 3)
        #expect(gate.activeTripLimit(for: EntitlementState(userTier: .royale, familyId: nil, wasEverInFamily: false, familyRole: nil, tags: [], creatorTierForFamily: nil)) == nil)
        #expect(gate.activeTripLimit(for: EntitlementState(userTier: .signedUp, familyId: "family1", wasEverInFamily: true, familyRole: "member", tags: [], creatorTierForFamily: .gold)) == 3)
        #expect(gate.activeTripLimit(for: EntitlementState(userTier: .signedUp, familyId: "family1", wasEverInFamily: true, familyRole: "member", tags: [], creatorTierForFamily: .royale)) == nil)
    }

    @Test func belowLimitAllowsActiveTripWithoutLogging() throws {
        let sessionRepo = MockTripSessionRepository()
        let bridge = MockRevenueCatBridge(tier: .gold)
        let entitlementService = EntitlementService(revenueCatBridge: bridge)
        entitlementService.setCurrentUserId("user1")
        let analytics = AnalyticsLoggingSpy()
        let gate = TripEntitlementGate(
            tripSessionRepository: sessionRepo,
            entitlementService: entitlementService,
            analytics: analytics
        )
        let user = makeUser()

        sessionRepo.seed(TripSession(id: UUID(), name: "Created", status: .created, createdAt: Date(), createdBy: "user1", participants: []))
        sessionRepo.seed(TripSession(id: UUID(), name: "Active", status: .active, createdAt: Date(), createdBy: "user1", startedAt: Date(), participants: []))

        try gate.validateCanAddActiveTrip(user: user, userId: "user1", source: .create)

        #expect(analytics.loggedEvents.isEmpty)
    }

    @Test func limitReachedThrowsAndLogsTripLimitHit() throws {
        let sessionRepo = MockTripSessionRepository()
        let bridge = MockRevenueCatBridge(tier: .guest)
        let entitlementService = EntitlementService(revenueCatBridge: bridge)
        entitlementService.setCurrentUserId("user1")
        let analytics = AnalyticsLoggingSpy()
        let gate = TripEntitlementGate(
            tripSessionRepository: sessionRepo,
            entitlementService: entitlementService,
            analytics: analytics
        )
        let user = makeUser()
        sessionRepo.seed(TripSession(id: UUID(), name: "Created", status: .created, createdAt: Date(), createdBy: "user1", participants: []))

        do {
            try gate.validateCanAddActiveTrip(user: user, userId: "user1", source: .inviteAccept)
            Issue.record("Expected active trip limit to throw")
        } catch let error as TripEntitlementGateError {
            #expect(error == .activeTripLimitReached(limit: 1, currentCount: 1, tier: .signedUp, source: .inviteAccept))
        }

        #expect(analytics.loggedEvents.count == 1)
        #expect(analytics.loggedEvents[0].name == "trip_limit_hit")
        #expect(analytics.loggedEvents[0].parameters?["source"] as? String == TripLimitGateSource.inviteAccept.rawValue)
        #expect(analytics.loggedEvents[0].parameters?["active_trip_count"] as? Int == 1)
        #expect(analytics.loggedEvents[0].parameters?["active_trip_limit"] as? Int == 1)
        #expect(analytics.loggedEvents[0].parameters?["tier"] as? String == UserTier.signedUp.rawValue)
    }

    @Test func startAllowsAlreadyCountedCreatedSessionAtLimit() throws {
        let sessionRepo = MockTripSessionRepository()
        let bridge = MockRevenueCatBridge(tier: .guest)
        let entitlementService = EntitlementService(revenueCatBridge: bridge)
        entitlementService.setCurrentUserId("user1")
        let analytics = AnalyticsLoggingSpy()
        let gate = TripEntitlementGate(
            tripSessionRepository: sessionRepo,
            entitlementService: entitlementService,
            analytics: analytics
        )
        let user = makeUser()
        let sessionId = UUID()
        sessionRepo.seed(TripSession(id: sessionId, name: "Created", status: .created, createdAt: Date(), createdBy: "user1", participants: []))

        try gate.validateCanStartTrip(user: user, userId: "user1", sessionId: sessionId)

        #expect(analytics.loggedEvents.isEmpty)
    }
}
