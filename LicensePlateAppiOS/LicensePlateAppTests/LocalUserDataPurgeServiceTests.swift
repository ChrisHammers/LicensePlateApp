//
//  LocalUserDataPurgeServiceTests.swift
//  LicensePlateAppTests
//
//  Hard sign-out wipe: representative entities deleted; device prefs kept; sync not flushed.
//

import Foundation
import SwiftData
import Testing
@testable import LicensePlateApp

@MainActor
struct LocalUserDataPurgeServiceTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [config]
        )
        return ModelContext(container)
    }

    private func wireSharedRepos(to ctx: ModelContext) {
        SyncQueueRepository.shared.setModelContext(ctx)
        PendingTripLeaveRepository.shared.setModelContext(ctx)
        TripSessionRepository.shared.setModelContext(ctx)
        TripActivityEventRepository.shared.setModelContext(ctx)
        GameInstanceRepository.shared.setModelContext(ctx)
        TripRoutePointRepository.shared.setModelContext(ctx)
        DiscoveryResolutionRepository.shared.setModelContext(ctx)
        XpLedgerRepository.shared.setModelContext(ctx)
        UserAchievementRepository.shared.setModelContext(ctx)
        UserLifetimeStatsRepository.shared.setModelContext(ctx)
        PublicLifetimeStatsRepository.shared.setModelContext(ctx)
        FriendshipRepository.shared.setModelContext(ctx)
        InviteRepository.shared.setModelContext(ctx)
        FamilyRepository.shared.setModelContext(ctx)
        TripInviteRepository.shared.setModelContext(ctx)
        UserRepository.shared.setModelContext(ctx)
    }

    @Test func purgeDeletesUserTripsSyncQueueAndProfileRows() async throws {
        let ctx = try makeContext()
        wireSharedRepos(to: ctx)
        defer { SyncCoordinator.shared.resumeProcessingAfterPurge() }

        let userId = "purge-user-\(UUID().uuidString)"
        let user = AppUser(
            id: userId,
            userName: "NamedPlayer",
            firstName: "Ada",
            lastName: "Lovelace",
            email: "ada@example.com",
            firebaseUID: userId
        )
        ctx.insert(user)
        try ctx.save()

        let session = TripSession(
            name: "Purge Trip",
            status: .active,
            createdBy: userId,
            startedAt: Date(),
            participants: [TripParticipant(userId: userId, role: .owner)]
        )
        try TripSessionRepository.shared.create(session: session)

        try TripActivityEventRepository.shared.append(
            TripActivityEvent(sessionId: session.id, kind: .tripStarted, actorId: userId)
        )

        let game = MockGameFactory.makeLicensePlateGame(sessionId: session.id)
        try GameInstanceRepository.shared.create(instance: game)

        try SyncQueueRepository.shared.enqueue(
            SyncQueueItem(
                id: UUID().uuidString,
                kind: .gameplayEvent,
                state: .pending,
                attemptCount: 0,
                createdAt: .now,
                updatedAt: .now,
                payloadSessionId: session.id.uuidString,
                payloadEventId: "evt-purge"
            )
        )
        try SyncQueueRepository.shared.saveMetadata(
            RemoteSyncMetadata(key: "cursor.\(userId)", lastSyncedAt: .now, valueData: nil)
        )
        try PendingTripLeaveRepository.shared.insertPending(sessionId: session.id, userId: userId)

        let defaults = UserDefaults.standard
        let deviceKey = "com.HammersTech.LicensePlateApp.deviceIdentifier"
        let priorDeviceId = defaults.string(forKey: deviceKey)
        defaults.set("device-keep-me", forKey: deviceKey)
        defaults.set(["session-a"], forKey: "tripEnd.pendingAutoRecapSessionIds")
        defaults.set(3, forKey: "returnStreak.\(userId).currentStreak")
        defer {
            if let priorDeviceId {
                defaults.set(priorDeviceId, forKey: deviceKey)
            } else {
                defaults.removeObject(forKey: deviceKey)
            }
        }

        try LocalUserDataPurgeService.shared.purgeAllLocalUserData(oldUserId: userId)

        #expect(try TripSessionRepository.shared.loadActiveSessions(userId: userId).isEmpty)
        #expect(try TripActivityEventRepository.shared.events(sessionId: session.id, limit: nil).isEmpty)
        #expect(try GameInstanceRepository.shared.fetchByTripSession(sessionId: session.id).isEmpty)
        #expect(try SyncQueueRepository.shared.fetchPending(limit: 10).isEmpty)
        #expect(try SyncQueueRepository.shared.metadata(key: "cursor.\(userId)") == nil)
        #expect(try PendingTripLeaveRepository.shared.sessionIdsPendingLeave(userId: userId).isEmpty)

        let users = try ctx.fetch(FetchDescriptor<AppUser>())
        #expect(users.isEmpty)

        #expect(defaults.string(forKey: deviceKey) == "device-keep-me")
        #expect(defaults.stringArray(forKey: "tripEnd.pendingAutoRecapSessionIds") == nil)
        #expect(defaults.object(forKey: "returnStreak.\(userId).currentStreak") == nil)
    }

    @Test func syncCoordinatorSuspendBlocksProcessPending() async throws {
        let ctx = try makeContext()
        let repo = SyncQueueRepository.shared
        repo.setModelContext(ctx)
        let coordinator = SyncCoordinator(repository: repo)

        try coordinator.enqueueForSync(sessionId: UUID(), eventId: "evt-suspend")
        #expect(try repo.fetchPending(limit: 10).count == 1)

        coordinator.suspendProcessingForPurge()
        defer { coordinator.resumeProcessingAfterPurge() }

        await coordinator.processPendingSyncItems()
        // Suspended: must not mark in-progress / complete; row stays pending.
        let pending = try repo.fetchPending(limit: 10)
        #expect(pending.count == 1)
        #expect(pending[0].state == .pending)
    }

    @Test func deleteAllLocalOnSyncQueueClearsMetadataWithoutUpload() async throws {
        let ctx = try makeContext()
        let repo = SyncQueueRepository.shared
        repo.setModelContext(ctx)

        try repo.enqueue(
            SyncQueueItem(
                id: UUID().uuidString,
                kind: .userProfile,
                state: .pending,
                attemptCount: 0,
                createdAt: .now,
                updatedAt: .now,
                payloadData: "user-1".data(using: .utf8)
            )
        )
        try repo.saveMetadata(RemoteSyncMetadata(key: "test-meta", lastSyncedAt: .now, valueData: Data([1])))

        try repo.deleteAllLocal()

        #expect(try repo.fetchPending(limit: 10).isEmpty)
        #expect(try repo.metadata(key: "test-meta") == nil)
    }

    @Test func guestRebirthUsesDeviceDefaultUsernamePattern() async throws {
        let deviceId = DeviceIdentifier.getDeviceIdentifier()
        let username = DeviceIdentifier.generateDefaultUsername(deviceId: deviceId)
        #expect(username.hasPrefix("User"))
        #expect(username.count >= 12)
        #expect(!username.contains(" "))
    }
}
