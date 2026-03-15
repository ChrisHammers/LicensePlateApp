//
//  TravelLogViewModelTests.swift
//  LicensePlateAppTests
//
//  Step 07 — TravelLogViewModel: load entries, open summary (discoveries from TripActivityEventRepository).
//

import Foundation
import SwiftData
import Testing
@testable import LicensePlateApp

@MainActor
struct TravelLogViewModelTests {

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

    @Test func loadEntriesPopulatesFromRepository() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        TravelLogRepository.shared.setModelContext(ctx)
        TripSessionRepository.shared.setModelContext(ctx)
        GameInstanceRepository.shared.setModelContext(ctx)
        TripActivityEventRepository.shared.setModelContext(ctx)

        let sessionId = UUID().uuidString
        let endedAt = Date().addingTimeInterval(-50)
        let entity = TripSessionEntity(
            id: sessionId,
            name: "Past Trip",
            status: TripStatus.ended.rawValue,
            mode: TripMode.solo.rawValue,
            endedAt: endedAt
        )
        ctx.insert(entity)
        try ctx.save()

        let auth = FirebaseAuthService()
        let viewModel = TravelLogViewModel(
            travelLogRepository: TravelLogRepository.shared,
            tripSessionRepository: TripSessionRepository.shared,
            gameInstanceRepository: GameInstanceRepository.shared,
            tripActivityEventRepository: TripActivityEventRepository.shared,
            authService: auth
        )
        viewModel.loadEntries(statusFilter: .endedOnly)

        #expect(viewModel.entries.count == 1)
        #expect(viewModel.entries[0].tripName == "Past Trip")
        #expect(viewModel.errorMessage == nil)
    }

    @Test func openSummaryBuildsSummaryWithEmptyDiscoveries() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        TravelLogRepository.shared.setModelContext(ctx)
        TripSessionRepository.shared.setModelContext(ctx)
        GameInstanceRepository.shared.setModelContext(ctx)
        TripActivityEventRepository.shared.setModelContext(ctx)

        let sessionId = UUID()
        let endedAt = Date().addingTimeInterval(-50)
        let entity = TripSessionEntity(
            id: sessionId.uuidString,
            name: "New Flow Trip",
            status: TripStatus.ended.rawValue,
            mode: TripMode.solo.rawValue,
            endedAt: endedAt,
            legacyTripId: nil
        )
        ctx.insert(entity)
        try ctx.save()

        let auth = FirebaseAuthService()
        let viewModel = TravelLogViewModel(
            travelLogRepository: TravelLogRepository.shared,
            tripSessionRepository: TripSessionRepository.shared,
            gameInstanceRepository: GameInstanceRepository.shared,
            tripActivityEventRepository: TripActivityEventRepository.shared,
            authService: auth
        )
        viewModel.openSummary(sessionId: sessionId)

        #expect(viewModel.selectedSummary != nil)
        #expect(viewModel.selectedSummary?.tripName == "New Flow Trip")
        #expect(viewModel.selectedSummary?.totalDiscoveryCount == 0)
        #expect(viewModel.selectedSummary?.participantContributions.isEmpty == true)
    }

    @Test func openSummaryWithEventsBuildsSummaryWithDiscoveries() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        TravelLogRepository.shared.setModelContext(ctx)
        TripSessionRepository.shared.setModelContext(ctx)
        GameInstanceRepository.shared.setModelContext(ctx)
        TripActivityEventRepository.shared.setModelContext(ctx)

        let sessionId = UUID()
        let gameId = UUID()
        let endedAt = Date().addingTimeInterval(-10)
        let entity = TripSessionEntity(
            id: sessionId.uuidString,
            name: "Trip With Plates",
            status: TripStatus.ended.rawValue,
            mode: TripMode.solo.rawValue,
            endedAt: endedAt,
            legacyTripId: nil
        )
        ctx.insert(entity)
        try ctx.save()

        try TripActivityEventRepository.shared.append(TripActivityEvent(sessionId: sessionId, kind: .regionFound, payload: [TripActivityEventPayloadKey.regionId: "CA", TripActivityEventPayloadKey.gameInstanceId: gameId.uuidString, TripActivityEventPayloadKey.participantId: "user1", TripActivityEventPayloadKey.inputMethod: FoundRegion.InputMethod.list.rawValue]))
        try TripActivityEventRepository.shared.append(TripActivityEvent(sessionId: sessionId, kind: .regionFound, payload: [TripActivityEventPayloadKey.regionId: "TX", TripActivityEventPayloadKey.gameInstanceId: gameId.uuidString, TripActivityEventPayloadKey.participantId: "user1", TripActivityEventPayloadKey.inputMethod: FoundRegion.InputMethod.list.rawValue]))

        let auth = FirebaseAuthService()
        let viewModel = TravelLogViewModel(
            travelLogRepository: TravelLogRepository.shared,
            tripSessionRepository: TripSessionRepository.shared,
            gameInstanceRepository: GameInstanceRepository.shared,
            tripActivityEventRepository: TripActivityEventRepository.shared,
            authService: auth
        )
        viewModel.openSummary(sessionId: sessionId)

        #expect(viewModel.selectedSummary != nil)
        #expect(viewModel.selectedSummary?.tripName == "Trip With Plates")
        #expect(viewModel.selectedSummary?.totalDiscoveryCount == 2)
    }
}
