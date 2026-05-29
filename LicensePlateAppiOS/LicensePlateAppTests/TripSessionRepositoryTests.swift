//
//  TripSessionRepositoryTests.swift
//  LicensePlateAppTests
//
//  Step 03 — TripSessionRepository: create, load, update status, participants, save. In-memory SwiftData only.
//

import Foundation
import SwiftData
import Testing
@testable import LicensePlateApp

@MainActor
struct TripSessionRepositoryTests {

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

    @Test func createAndFetchSession() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let repo = TripSessionRepository.shared
        repo.setModelContext(context)

        let session = TripSession(name: "Repo Test Trip", status: .active)
        try repo.create(session: session)

        let loaded = try repo.session(byId: session.id)
        #expect(loaded != nil)
        #expect(loaded?.name == "Repo Test Trip")
        #expect(loaded?.status == .active)
        #expect(loaded?.mode == .solo)
    }

    @Test func loadActiveSessionsEmptyThenOne() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let repo = TripSessionRepository.shared
        repo.setModelContext(context)

        var active = try repo.loadActiveSessions(userId: nil)
        #expect(active.isEmpty)

        let session = TripSession(name: "Active Trip", status: .active, startedAt: Date())
        try repo.create(session: session)
        active = try repo.loadActiveSessions(userId: nil)
        #expect(active.count == 1)
        #expect(active[0].name == "Active Trip")
    }

    /// Step 02 — Documents that root active list is sourced from TripSessionRepository only (canonical model; no legacy Trip).
    @Test func activeListUsesCanonicalTripSessionRepositoryOnly() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let repo = TripSessionRepository.shared
        repo.setModelContext(context)
        let session = TripSession(name: "Canonical Active", status: .active, startedAt: Date())
        try repo.create(session: session)
        let active = try repo.loadActiveSessions(userId: nil)
        #expect(active.count == 1)
        #expect(active[0].id == session.id)
        #expect(active[0].name == "Canonical Active")
    }

    @Test func updateStatusToActiveThenEnded() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let repo = TripSessionRepository.shared
        repo.setModelContext(context)

        let session = TripSession(name: "Status Trip", status: .active)
        try repo.create(session: session)

        try repo.updateStatus(sessionId: session.id, status: .active)
        var loaded = try repo.session(byId: session.id)
        #expect(loaded?.status == .active)
        #expect(loaded?.startedAt != nil)

        try repo.updateStatus(sessionId: session.id, status: .ended)
        loaded = try repo.session(byId: session.id)
        #expect(loaded?.status == .ended)
        #expect(loaded?.endedAt != nil)
    }

    @Test func addAndRemoveParticipant() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let repo = TripSessionRepository.shared
        repo.setModelContext(context)

        let session = TripSession(name: "Participants Trip", status: .active, createdBy: "user1")
        try repo.create(session: session)

        let participant = TripParticipant(userId: "user2", role: .member)
        try repo.addParticipant(sessionId: session.id, participant: participant)

        var loaded = try repo.session(byId: session.id)
        #expect(loaded?.participants.count == 1)
        #expect(loaded?.participants.first?.userId == "user2")

        try repo.removeParticipant(sessionId: session.id, userId: "user2")
        loaded = try repo.session(byId: session.id)
        #expect(loaded?.participants.isEmpty == true)
    }

    @Test func saveUpsertUpdatesExisting() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let repo = TripSessionRepository.shared
        repo.setModelContext(context)

        let session = TripSession(name: "Original", status: .active)
        try repo.create(session: session)
        let id = session.id

        session.name = "Updated Name"
        session.status = .active
        try repo.save(session: session)

        let loaded = try repo.session(byId: id)
        #expect(loaded?.name == "Updated Name")
        #expect(loaded?.status == .active)
    }

    @Test func loadArchivedSessionsReturnsEndedOnly() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let repo = TripSessionRepository.shared
        repo.setModelContext(context)

        let endedSession = TripSession(name: "Ended Trip", status: .ended, endedAt: Date())
        try repo.create(session: endedSession)
        let activeSession = TripSession(name: "Active Trip", status: .active, startedAt: Date())
        try repo.create(session: activeSession)

        let archived = try repo.loadArchivedSessions(userId: nil, limit: 10, includeCancelled: false, sortBy: .endedAtDesc)
        #expect(archived.count == 1)
        #expect(archived[0].name == "Ended Trip")
    }

    @Test func loadArchivedSessionsIncludeCancelledFalseExcludesCancelled() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let repo = TripSessionRepository.shared
        repo.setModelContext(context)

        let endedSession = TripSession(name: "Ended", status: .ended, endedAt: Date())
        try repo.create(session: endedSession)
        var cancelledSession = TripSession(name: "Cancelled", status: .active)
        try repo.create(session: cancelledSession)
        try repo.updateStatus(sessionId: cancelledSession.id, status: .cancelled)

        let archived = try repo.loadArchivedSessions(userId: nil, limit: 10, includeCancelled: false, sortBy: .endedAtDesc)
        #expect(archived.count == 1)
        #expect(archived[0].name == "Ended")
    }

    @Test func loadArchivedSessionsSortByEndedAtAsc() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let repo = TripSessionRepository.shared
        repo.setModelContext(context)

        let older = Date().addingTimeInterval(-200)
        let newer = Date().addingTimeInterval(-100)
        let session1 = TripSession(name: "Older", status: .ended, endedAt: older)
        let session2 = TripSession(name: "Newer", status: .ended, endedAt: newer)
        try repo.create(session: session1)
        try repo.create(session: session2)

        let archived = try repo.loadArchivedSessions(userId: nil, limit: 10, includeCancelled: true, sortBy: .endedAtAsc)
        #expect(archived.count == 2)
        #expect(archived[0].name == "Older")
        #expect(archived[1].name == "Newer")
    }

    @Test func lastSyncedAtReturnsNil() async throws {
        let repo = TripSessionRepository.shared
        #expect(repo.lastSyncedAt(sessionId: UUID()) == nil)
    }

    /// Step 05 — Failure: updateStatus throws sessionNotFound when session does not exist.
    @Test func updateStatusThrowsSessionNotFoundWhenSessionMissing() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let repo = TripSessionRepository.shared
        repo.setModelContext(context)

        let unknownId = UUID()
        do {
            try repo.updateStatus(sessionId: unknownId, status: .ended)
            Issue.record("Expected TripSessionRepositoryError.sessionNotFound")
        } catch let error as TripSessionRepositoryError {
            if case .sessionNotFound(let id) = error {
                #expect(id == unknownId)
            } else {
                Issue.record("Expected sessionNotFound, got \(error)")
            }
        }
    }

    /// Step 6.9.1 — Session with participants (including teamId) round-trips. Teams are on GameInstance; see GameInstanceRepositoryTests for game teams.
    @Test func sessionWithParticipantTeamIdsRoundTrips() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let repo = TripSessionRepository.shared
        repo.setModelContext(context)

        let team1 = TripTeam(name: "Team A", participantUserIds: ["user1", "user2"])
        let participant1 = TripParticipant(userId: "user1", role: .owner, teamId: team1.id)
        let participant2 = TripParticipant(userId: "user2", role: .member, teamId: team1.id)
        let session = TripSession(
            name: "Team Trip",
            status: .active,
            createdAt: Date(),
            createdBy: "user1",
            startedAt: Date(),
            participants: [participant1, participant2]
        )
        try repo.create(session: session)

        let loaded = try repo.session(byId: session.id)
        #expect(loaded != nil)
        #expect(loaded?.participants.count == 2)
        #expect(loaded?.participants.first { $0.userId == "user1" }?.teamId == team1.id)
    }

    /// Step 14 — Active list hides trips with a pending voluntary leave row for that user.
    @Test func loadActiveSessionsExcludesPendingLeaveForUser() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let repo = TripSessionRepository.shared
        repo.setModelContext(context)
        PendingTripLeaveRepository.shared.setModelContext(context)

        let session = TripSession(
            name: "Shared",
            status: .active,
            createdAt: Date(),
            createdBy: "owner1",
            startedAt: Date(),
            participants: [
                TripParticipant(userId: "owner1", role: .owner, joinedAt: Date()),
                TripParticipant(userId: "joiner1", role: .member, joinedAt: Date())
            ]
        )
        try repo.create(session: session)

        var forJoiner = try repo.loadActiveSessions(userId: "joiner1")
        #expect(forJoiner.count == 1)

        try PendingTripLeaveRepository.shared.insertPending(sessionId: session.id, userId: "joiner1")
        forJoiner = try repo.loadActiveSessions(userId: "joiner1")
        #expect(forJoiner.isEmpty)
    }
}
