//
//  TripActivityEventRecordingServiceTests.swift
//  LicensePlateAppTests
//
//  Step 07 — TripActivityEventRecordingService: persist + enqueue integration, idempotency, retry after enqueue failure.
//

import Foundation
import SwiftData
import Testing
@testable import LicensePlateApp

@MainActor
struct TripActivityEventRecordingServiceTests {

    private func makeContainerContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: [config])
        return ModelContext(container)
    }

    @Test func recordForSyncPersistsAndEnqueuesOnce() async throws {
        let ctx = try makeContainerContext()
        TripActivityEventRepository.shared.setModelContext(ctx)
        SyncQueueRepository.shared.setModelContext(ctx)
        let coordinator = SyncCoordinator(repository: SyncQueueRepository.shared)
        let recording = TripActivityEventRecordingService(
            tripActivityEventRepository: TripActivityEventRepository.shared,
            syncCoordinator: coordinator
        )
        let sessionId = UUID()
        let event = TripActivityEvent(sessionId: sessionId, kind: .tripStarted, actorId: "u1")
        try recording.recordForSync(event)
        try recording.recordForSync(event)

        let events = try TripActivityEventRepository.shared.events(sessionId: sessionId, limit: nil)
        #expect(events.count == 1)

        let pending = try SyncQueueRepository.shared.fetchPending(limit: 10)
        #expect(pending.count == 1)
        #expect(pending[0].payloadEventId == event.id)
    }

    @Test func recordForSyncRetriesEnqueueAfterFirstFailure() async throws {
        let eventRepo = MockTripActivityEventRepository()
        let sync = MockSyncCoordinator()
        sync.pendingEnqueueForSyncError = NSError(domain: "Test", code: 1)
        let recording = TripActivityEventRecordingService(tripActivityEventRepository: eventRepo, syncCoordinator: sync)
        let sessionId = UUID()
        let gid = UUID().uuidString
        let event = TripActivityEvent(id: "e1", sessionId: sessionId, kind: .regionFound, actorId: "u1", payload: [
            TripActivityEventPayloadKey.regionId: "CA",
            TripActivityEventPayloadKey.gameInstanceId: gid,
            TripActivityEventPayloadKey.inputMethod: FoundRegion.InputMethod.list.rawValue
        ])
        do {
            try recording.recordForSync(event)
            #expect(Bool(false), "Expected first record to throw")
        } catch {
            #expect((error as NSError).domain == "Test")
        }
        #expect(eventRepo.appendedEvents().count == 1)
        #expect(sync.scheduleDebouncedGameplaySyncFlushCallCount == 0)

        try recording.recordForSync(event)
        #expect(eventRepo.appendedEvents().count == 1)
        #expect(sync.enqueueCallCount == 1)
        #expect(sync.enqueueEventIds == ["e1"])
        #expect(sync.scheduleDebouncedGameplaySyncFlushCallCount == 1)
    }

    @Test func recordForSyncSchedulesDebouncedFlushOncePerSuccessfulCall() throws {
        let eventRepo = MockTripActivityEventRepository()
        let sync = MockSyncCoordinator()
        let recording = TripActivityEventRecordingService(tripActivityEventRepository: eventRepo, syncCoordinator: sync)
        let sessionId = UUID()
        let event = TripActivityEvent(sessionId: sessionId, kind: .tripStarted, actorId: "u1")
        try recording.recordForSync(event)
        #expect(sync.scheduleDebouncedGameplaySyncFlushCallCount == 1)
        try recording.recordForSync(event)
        #expect(sync.scheduleDebouncedGameplaySyncFlushCallCount == 2)
    }
}
