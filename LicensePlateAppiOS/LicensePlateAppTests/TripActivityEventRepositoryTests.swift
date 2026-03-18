//
//  TripActivityEventRepositoryTests.swift
//  LicensePlateAppTests
//
//  Step 01 — TripActivityEventRepository: append events, derive discoveries/foundRegions from region_found/region_removed.
//

import Foundation
import SwiftData
import Testing
@testable import LicensePlateApp

@MainActor
struct TripActivityEventRepositoryTests {

    private func makeContainer() throws -> ModelContext {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: [config])
        let ctx = ModelContext(container)
        TripActivityEventRepository.shared.setModelContext(ctx)
        return ctx
    }

    @Test func appendAndFetchEvents() async throws {
        let ctx = try makeContainer()
        let sessionId = UUID()
        let event1 = TripActivityEvent(sessionId: sessionId, kind: .tripStarted, actorId: "user1")
        let event2 = TripActivityEvent(sessionId: sessionId, kind: .regionFound, payload: [TripActivityEventPayloadKey.regionId: "CA", TripActivityEventPayloadKey.gameInstanceId: UUID().uuidString, TripActivityEventPayloadKey.inputMethod: FoundRegion.InputMethod.list.rawValue])

        try TripActivityEventRepository.shared.append(event1)
        try TripActivityEventRepository.shared.append(event2)

        let events = try TripActivityEventRepository.shared.events(sessionId: sessionId, limit: nil)
        #expect(events.count == 2)
        #expect(events[0].kind == .tripStarted)
        #expect(events[1].kind == .regionFound)
    }

    @Test func foundRegionsDerivedFromReplay() async throws {
        let ctx = try makeContainer()
        let sessionId = UUID()
        let gameId = UUID()
        try TripActivityEventRepository.shared.append(TripActivityEvent(sessionId: sessionId, kind: .regionFound, payload: [TripActivityEventPayloadKey.regionId: "CA", TripActivityEventPayloadKey.gameInstanceId: gameId.uuidString, TripActivityEventPayloadKey.inputMethod: FoundRegion.InputMethod.list.rawValue]))
        try TripActivityEventRepository.shared.append(TripActivityEvent(sessionId: sessionId, kind: .regionFound, payload: [TripActivityEventPayloadKey.regionId: "TX", TripActivityEventPayloadKey.gameInstanceId: gameId.uuidString, TripActivityEventPayloadKey.inputMethod: FoundRegion.InputMethod.voice.rawValue]))

        let regions = try TripActivityEventRepository.shared.foundRegions(sessionId: sessionId, gameInstanceId: gameId)
        #expect(regions.count == 2)
        #expect(regions.map(\.regionID).sorted() == ["CA", "TX"])
    }

    @Test func regionRemovedRemovesFromDerivedFoundRegions() async throws {
        let ctx = try makeContainer()
        let sessionId = UUID()
        let gameId = UUID()
        try TripActivityEventRepository.shared.append(TripActivityEvent(sessionId: sessionId, kind: .regionFound, payload: [TripActivityEventPayloadKey.regionId: "CA", TripActivityEventPayloadKey.gameInstanceId: gameId.uuidString, TripActivityEventPayloadKey.inputMethod: FoundRegion.InputMethod.list.rawValue]))
        try TripActivityEventRepository.shared.append(TripActivityEvent(sessionId: sessionId, kind: .regionFound, payload: [TripActivityEventPayloadKey.regionId: "TX", TripActivityEventPayloadKey.gameInstanceId: gameId.uuidString, TripActivityEventPayloadKey.inputMethod: FoundRegion.InputMethod.list.rawValue]))
        try TripActivityEventRepository.shared.append(TripActivityEvent(sessionId: sessionId, kind: .regionRemoved, payload: [TripActivityEventPayloadKey.regionId: "CA", TripActivityEventPayloadKey.gameInstanceId: gameId.uuidString]))

        let regions = try TripActivityEventRepository.shared.foundRegions(sessionId: sessionId, gameInstanceId: gameId)
        #expect(regions.count == 1)
        #expect(regions[0].regionID == "TX")
    }

    /// Step 05 — Failure: append throws when mock is configured to throw (failure propagation).
    @Test func appendThrowsWhenMockConfiguredToThrow() async throws {
        let mock = MockTripActivityEventRepository()
        mock.shouldThrow = true
        let event = TripActivityEvent(sessionId: UUID(), kind: .tripStarted, actorId: "u1")
        do {
            try mock.append(event)
            #expect(Bool(false), "Expected append to throw")
        } catch {
            #expect((error as NSError).domain == "MockTripActivityEventRepository")
        }
    }
}
