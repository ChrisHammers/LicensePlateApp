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

        let session = TripSession(name: "Repo Test Trip", status: .draft, mode: .solo)
        try repo.create(session: session)

        let loaded = try repo.session(byId: session.id)
        #expect(loaded != nil)
        #expect(loaded?.name == "Repo Test Trip")
        #expect(loaded?.status == .draft)
        #expect(loaded?.mode == .solo)
    }

    @Test func loadActiveSessionsEmptyThenOne() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let repo = TripSessionRepository.shared
        repo.setModelContext(context)

        var active = try repo.loadActiveSessions(userId: nil)
        #expect(active.isEmpty)

        let session = TripSession(name: "Active Trip", status: .active, mode: .solo, startedAt: Date())
        try repo.create(session: session)
        active = try repo.loadActiveSessions(userId: nil)
        #expect(active.count == 1)
        #expect(active[0].name == "Active Trip")
    }

    @Test func updateStatusToActiveThenEnded() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let repo = TripSessionRepository.shared
        repo.setModelContext(context)

        let session = TripSession(name: "Status Trip", status: .draft, mode: .solo)
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

        let session = TripSession(name: "Participants Trip", status: .active, mode: .collaborative, createdBy: "user1")
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

        let session = TripSession(name: "Original", status: .draft, mode: .solo)
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

        let endedSession = TripSession(name: "Ended Trip", status: .ended, mode: .solo, endedAt: Date())
        try repo.create(session: endedSession)
        let activeSession = TripSession(name: "Active Trip", status: .active, mode: .solo, startedAt: Date())
        try repo.create(session: activeSession)

        let archived = try repo.loadArchivedSessions(userId: nil, limit: 10)
        #expect(archived.count == 1)
        #expect(archived[0].name == "Ended Trip")
    }

    @Test func lastSyncedAtReturnsNil() async throws {
        let repo = TripSessionRepository.shared
        #expect(repo.lastSyncedAt(sessionId: UUID()) == nil)
    }

    /// Step 06.5 — Session with teams and participant.teamId round-trips correctly.
    @Test func sessionWithTeamsRoundTrips() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let repo = TripSessionRepository.shared
        repo.setModelContext(context)

        let team1 = TripTeam(name: "Team A", participantUserIds: ["user1", "user2"])
        let team2 = TripTeam(name: "Team B", participantUserIds: ["user3"])
        let participant1 = TripParticipant(userId: "user1", role: .owner, teamId: team1.id)
        let participant2 = TripParticipant(userId: "user2", role: .member, teamId: team1.id)
        let session = TripSession(
            name: "Team Trip",
            status: .active,
            mode: .solo,
            createdBy: "user1",
            startedAt: Date(),
            participants: [participant1, participant2],
            teams: [team1, team2]
        )
        try repo.create(session: session)

        let loaded = try repo.session(byId: session.id)
        #expect(loaded != nil)
        #expect(loaded?.teams.count == 2)
        #expect(loaded?.teams.first { $0.name == "Team A" }?.participantUserIds == ["user1", "user2"])
        #expect(loaded?.participants.count == 2)
        #expect(loaded?.participants.first { $0.userId == "user1" }?.teamId == team1.id)
    }
}
