//
//  TripInviteRepositoryTests.swift
//  LicensePlateAppTests
//
//  Step 11.5 — TripInviteRepository helper queries.
//

import Foundation
import SwiftData
import Testing
@testable import LicensePlateApp

@MainActor
struct TripInviteRepositoryTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: [config])
    }

    @Test func getInvitesForTripSessionIdFiltersRows() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let repo = TripInviteRepository(tripSessionRepository: .shared)
        repo.setModelContext(context)

        let target = UUID().uuidString
        context.insert(TripInvite(inviteId: "i1", tripSessionId: target, tripName: "Trip A", fromUserId: "u1", toUserId: "u2", status: .pending, createdAt: .now, expiresAt: .now.addingTimeInterval(60)))
        context.insert(TripInvite(inviteId: "i2", tripSessionId: "other", tripName: "Trip B", fromUserId: "u1", toUserId: "u3", status: .pending, createdAt: .now, expiresAt: .now.addingTimeInterval(60)))
        try context.save()

        let rows = try repo.getInvites(forTripSessionId: target)
        #expect(rows.count == 1)
        #expect(rows.first?.tripSessionId == target)
    }

    @Test func hasPendingInviteChecksStatusAndRecipient() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let repo = TripInviteRepository(tripSessionRepository: .shared)
        repo.setModelContext(context)

        let target = UUID().uuidString
        context.insert(TripInvite(inviteId: "i1", tripSessionId: target, tripName: "Trip A", fromUserId: "u1", toUserId: "u2", status: .pending, createdAt: .now, expiresAt: .now.addingTimeInterval(60)))
        context.insert(TripInvite(inviteId: "i2", tripSessionId: target, tripName: "Trip A", fromUserId: "u1", toUserId: "u3", status: .accepted, createdAt: .now, expiresAt: .now.addingTimeInterval(60)))
        try context.save()

        #expect(try repo.hasPendingInvite(tripSessionId: target, toUserId: "u2"))
        #expect(!(try repo.hasPendingInvite(tripSessionId: target, toUserId: "u3")))
    }
}
