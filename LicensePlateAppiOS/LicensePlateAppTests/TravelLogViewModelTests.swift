//
//  TravelLogViewModelTests.swift
//  LicensePlateAppTests
//
//  Step 07 — TravelLogViewModel: load entries, open summary (with and without legacy trip).
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
        TripRepository.shared.setModelContext(ctx)

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
            tripRepository: TripRepository.shared,
            authService: auth
        )
        viewModel.loadEntries(statusFilter: .endedOnly)

        #expect(viewModel.entries.count == 1)
        #expect(viewModel.entries[0].tripName == "Past Trip")
        #expect(viewModel.errorMessage == nil)
    }

    @Test func openSummaryWithoutLegacyBuildsSummaryWithEmptyDiscoveries() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        TravelLogRepository.shared.setModelContext(ctx)
        TripSessionRepository.shared.setModelContext(ctx)
        GameInstanceRepository.shared.setModelContext(ctx)
        TripRepository.shared.setModelContext(ctx)

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
            tripRepository: TripRepository.shared,
            authService: auth
        )
        viewModel.openSummary(sessionId: sessionId)

        #expect(viewModel.selectedSummary != nil)
        #expect(viewModel.selectedSummary?.tripName == "New Flow Trip")
        #expect(viewModel.selectedSummary?.totalDiscoveryCount == 0)
        #expect(viewModel.selectedSummary?.participantContributions.isEmpty == true)
    }

    @Test func openSummaryWithLegacyTripBuildsSummaryWithDiscoveries() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        TravelLogRepository.shared.setModelContext(ctx)
        TripSessionRepository.shared.setModelContext(ctx)
        GameInstanceRepository.shared.setModelContext(ctx)
        TripRepository.shared.setModelContext(ctx)

        let tripId = UUID()
        let sessionId = tripId
        let createdAt = Date().addingTimeInterval(-200)
        let endedAt = Date().addingTimeInterval(-10)
        let legacyTrip = Trip(
            id: tripId,
            createdAt: createdAt,
            lastUpdated: endedAt,
            name: "Legacy Trip",
            foundRegions: [
                FoundRegion(regionID: "CA", foundAt: createdAt, inputMethod: .list, foundBy: "user1"),
                FoundRegion(regionID: "TX", foundAt: createdAt.addingTimeInterval(10), inputMethod: .list, foundBy: "user1")
            ],
            createdBy: "user1",
            startedAt: createdAt,
            isTripEnded: true,
            tripEndedAt: endedAt,
            tripEndedBy: "user1",
            enabledCountries: [.unitedStates]
        )
        ctx.insert(legacyTrip)
        try ctx.save()

        let entity = TripSessionEntity(
            id: sessionId.uuidString,
            name: "Legacy Trip",
            status: TripStatus.ended.rawValue,
            mode: TripMode.solo.rawValue,
            endedAt: endedAt,
            legacyTripId: tripId.uuidString
        )
        ctx.insert(entity)
        try ctx.save()

        let auth = FirebaseAuthService()
        let viewModel = TravelLogViewModel(
            travelLogRepository: TravelLogRepository.shared,
            tripSessionRepository: TripSessionRepository.shared,
            gameInstanceRepository: GameInstanceRepository.shared,
            tripRepository: TripRepository.shared,
            authService: auth
        )
        viewModel.openSummary(sessionId: sessionId)

        #expect(viewModel.selectedSummary != nil)
        #expect(viewModel.selectedSummary?.tripName == "Legacy Trip")
        #expect(viewModel.selectedSummary?.totalDiscoveryCount == 2)
        #expect(viewModel.selectedSummary?.participantContributions.isEmpty == false)
    }
}
