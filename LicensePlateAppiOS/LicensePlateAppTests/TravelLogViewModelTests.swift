//
//  TravelLogViewModelTests.swift
//  LicensePlateAppTests
//
//  Step 07 — TravelLogViewModel: load entries, open summary (discoveries from TripActivityEventRepository).
//

import Foundation
import SwiftData
import Testing
import UIKit
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
            status: TripSessionState.ended.rawValue,
            createdAt: endedAt.addingTimeInterval(-100),
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
            status: TripSessionState.ended.rawValue,
            createdAt: endedAt.addingTimeInterval(-100),
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
        viewModel.openSummary(sessionId: sessionId)

        #expect(viewModel.selectedSummary != nil)
        #expect(viewModel.selectedSummary?.sessionId == sessionId)
        #expect(viewModel.selectedSummary?.tripName == "New Flow Trip")
        #expect(viewModel.selectedSummary?.totalDiscoveryCount == 0)
        #expect(viewModel.selectedSummary?.rankedParticipants.isEmpty == true)
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
            status: TripSessionState.ended.rawValue,
            createdAt: endedAt.addingTimeInterval(-100),
            endedAt: endedAt
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
        #expect(viewModel.selectedSummary?.sessionId == sessionId)
        #expect(viewModel.selectedSummary?.tripName == "Trip With Plates")
        #expect(viewModel.selectedSummary?.totalDiscoveryCount == 2)
    }

    // MARK: - Step 15 recap errors & projections

    @Test func openSummaryFailureSetsSummaryErrorWithoutClearingListError() async throws {
        let mockTrip = MockTripSessionRepository()
        let mockGame = MockGameInstanceRepository()
        let mockEvents = MockTripActivityEventRepository()
        let mockLog = MockTravelLogRepository()

        let sessionId = UUID()
        let session = TripSession(
            id: sessionId,
            name: "Fails Fetch",
            status: .ended,
            createdAt: Date().addingTimeInterval(-200),
            endedAt: Date().addingTimeInterval(-100),
            participants: [TripParticipant(userId: "u1", role: .owner)]
        )
        mockTrip.seed(session)
        mockGame.shouldThrow = true

        let viewModel = TravelLogViewModel(
            travelLogRepository: mockLog,
            tripSessionRepository: mockTrip,
            gameInstanceRepository: mockGame,
            tripActivityEventRepository: mockEvents,
            authService: FirebaseAuthService()
        )
        viewModel.errorMessage = "List load failed"

        viewModel.openSummary(sessionId: sessionId)

        #expect(viewModel.summaryErrorMessage != nil)
        #expect(viewModel.selectedSummary == nil)
        #expect(viewModel.errorMessage == "List load failed")
    }

    @Test func clearSelectionClearsSummaryError() async throws {
        let mockTrip = MockTripSessionRepository()
        let mockGame = MockGameInstanceRepository()
        let mockEvents = MockTripActivityEventRepository()
        let mockLog = MockTravelLogRepository()

        let sessionId = UUID()
        let session = TripSession(
            id: sessionId,
            name: "X",
            status: .ended,
            createdAt: Date(),
            endedAt: Date(),
            participants: [TripParticipant(userId: "u1", role: .owner)]
        )
        mockTrip.seed(session)
        mockGame.shouldThrow = true

        let viewModel = TravelLogViewModel(
            travelLogRepository: mockLog,
            tripSessionRepository: mockTrip,
            gameInstanceRepository: mockGame,
            tripActivityEventRepository: mockEvents,
            authService: FirebaseAuthService()
        )
        viewModel.openSummary(sessionId: sessionId)
        #expect(viewModel.summaryErrorMessage != nil)

        viewModel.clearSelection()
        #expect(viewModel.summaryErrorMessage == nil)
        #expect(viewModel.selectedSummary == nil)
    }

    @Test func openSummaryAttachesXpRecapLinesFromLedger() async throws {
        let sessionId = UUID()
        let gameId = UUID()
        let uid = "ledger_recap_user"

        let session = TripSession(
            id: sessionId,
            name: "Ledger recap trip",
            status: .ended,
            createdAt: Date().addingTimeInterval(-200),
            endedAt: Date().addingTimeInterval(-100),
            participants: [TripParticipant(userId: uid, role: .owner)]
        )
        let lpData = try JSONEncoder().encode(LicensePlateGameConfig())
        let game = GameInstance(
            id: gameId,
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: "license_plate"),
            commonConfig: CommonGameConfig(lifecycleState: .completed, gameMode: .collaborative),
            gameSpecificPayloadType: "license_plate",
            gameSpecificPayloadVersion: "1",
            gameSpecificPayloadData: lpData
        )

        let mockTrip = MockTripSessionRepository()
        mockTrip.seed(session)
        let mockGame = MockGameInstanceRepository()
        mockGame.seed(game)
        let mockEvents = MockTripActivityEventRepository()

        let mockLedger = MockXpLedgerRepository()
        let key = XpLedgerKeyBuilder.uniquenessKey(
            userId: uid,
            sessionId: sessionId,
            gameInstanceId: gameId,
            itemId: "us-ny",
            xpCategory: .baseRegionDiscovery
        ).storageString
        try mockLedger.append(
            XpLedgerEvent(
                userId: uid,
                sessionId: sessionId,
                gameInstanceId: gameId,
                sourceEventId: "ev1",
                sourceEventType: "region_found",
                itemId: "us-ny",
                grantKind: .provisionalDiscoveryXp,
                status: .provisional,
                xpDelta: 10,
                reasonCode: .discoveryClaimPendingResolution,
                xpUniquenessKey: key
            )
        )

        let auth = FirebaseAuthService()
        auth.currentUser = AppUser(id: uid, userName: "U", firebaseUID: uid)

        let viewModel = TravelLogViewModel(
            travelLogRepository: MockTravelLogRepository(),
            tripSessionRepository: mockTrip,
            gameInstanceRepository: mockGame,
            tripActivityEventRepository: mockEvents,
            authService: auth,
            xpLedger: mockLedger
        )
        viewModel.openSummary(sessionId: sessionId)

        #expect(viewModel.selectedSummary != nil)
        #expect(viewModel.selectedSummary?.xpRecapLines.isEmpty == false)
    }

    @Test func anonymousUserShowsThreeNewestSavedTripsAndHiddenCount() async throws {
        let uid = "anon_saved_trips"
        let auth = FirebaseAuthService()
        auth.currentUser = AppUser(id: uid, userName: "Anon", firebaseUID: uid)

        let entitlementService = EntitlementService(
            revenueCatBridge: MockRevenueCatBridge(tier: .guest),
            accountStateProvider: StaticAccountStateProvider(.firebaseAnonymous)
        )
        entitlementService.setCurrentUserId(uid)

        let mockLog = MockTravelLogRepository()
        mockLog.setSummaryProjections(Self.travelLogEntries(count: 6))
        let analytics = AnalyticsLoggingSpy()
        let viewModel = TravelLogViewModel(
            travelLogRepository: mockLog,
            tripSessionRepository: MockTripSessionRepository(),
            gameInstanceRepository: MockGameInstanceRepository(),
            tripActivityEventRepository: MockTripActivityEventRepository(),
            authService: auth,
            savedTripAccessPolicy: SavedTripAccessPolicy(
                entitlementService: entitlementService,
                accountStateProvider: StaticAccountStateProvider(.firebaseAnonymous)
            ),
            analytics: analytics
        )

        viewModel.loadEntries(statusFilter: .endedOnly)

        #expect(viewModel.entries.count == 3)
        #expect(viewModel.hiddenSavedTripCount == 3)
        #expect(analytics.loggedEvents.contains { $0.name == "saved_trip_limit_hit" })
    }

    @Test func signedUpFreeUserShowsFiveNewestSavedTripsAndHiddenCount() async throws {
        let uid = "signed_saved_trips"
        let auth = FirebaseAuthService()
        auth.currentUser = AppUser(id: uid, userName: "Signed", firebaseUID: uid)

        let entitlementService = EntitlementService(
            revenueCatBridge: MockRevenueCatBridge(tier: .guest),
            accountStateProvider: StaticAccountStateProvider(.signedIn)
        )
        entitlementService.setCurrentUserId(uid)

        let mockLog = MockTravelLogRepository()
        mockLog.setSummaryProjections(Self.travelLogEntries(count: 7))
        let viewModel = TravelLogViewModel(
            travelLogRepository: mockLog,
            tripSessionRepository: MockTripSessionRepository(),
            gameInstanceRepository: MockGameInstanceRepository(),
            tripActivityEventRepository: MockTripActivityEventRepository(),
            authService: auth,
            savedTripAccessPolicy: SavedTripAccessPolicy(
                entitlementService: entitlementService,
                accountStateProvider: StaticAccountStateProvider(.signedIn)
            ),
            analytics: AnalyticsLoggingSpy()
        )

        viewModel.loadEntries(statusFilter: .endedOnly)

        #expect(viewModel.entries.count == 5)
        #expect(viewModel.hiddenSavedTripCount == 2)
    }

    @Test func goldUserIsNotSavedTripCapped() async throws {
        let uid = "gold_saved_trips"
        let auth = FirebaseAuthService()
        auth.currentUser = AppUser(id: uid, userName: "Gold", firebaseUID: uid)

        let entitlementService = EntitlementService(
            revenueCatBridge: MockRevenueCatBridge(tier: .gold),
            accountStateProvider: StaticAccountStateProvider(.signedIn)
        )
        entitlementService.setCurrentUserId(uid)

        let mockLog = MockTravelLogRepository()
        mockLog.setSummaryProjections(Self.travelLogEntries(count: 7))
        let viewModel = TravelLogViewModel(
            travelLogRepository: mockLog,
            tripSessionRepository: MockTripSessionRepository(),
            gameInstanceRepository: MockGameInstanceRepository(),
            tripActivityEventRepository: MockTripActivityEventRepository(),
            authService: auth,
            savedTripAccessPolicy: SavedTripAccessPolicy(
                entitlementService: entitlementService,
                accountStateProvider: StaticAccountStateProvider(.signedIn)
            ),
            analytics: AnalyticsLoggingSpy()
        )

        viewModel.loadEntries(statusFilter: .endedOnly)

        #expect(viewModel.entries.count == 7)
        #expect(viewModel.hiddenSavedTripCount == 0)
    }

    @Test func openSummaryLocalEndLogsAutoPresentAnalyticsOnce() async throws {
        let sessionId = UUID()
        let mockTrip = MockTripSessionRepository()
        mockTrip.seed(TripSession(
            id: sessionId,
            name: "Ended",
            status: .ended,
            createdAt: Date(),
            endedAt: Date(),
            participants: []
        ))
        let analytics = AnalyticsLoggingSpy()
        let viewModel = TravelLogViewModel(
            travelLogRepository: MockTravelLogRepository(),
            tripSessionRepository: mockTrip,
            gameInstanceRepository: MockGameInstanceRepository(),
            tripActivityEventRepository: MockTripActivityEventRepository(),
            authService: FirebaseAuthService(),
            analytics: analytics
        )

        viewModel.openSummary(sessionId: sessionId, source: .localEnd)
        viewModel.openSummary(sessionId: sessionId, source: .remoteEnd)

        #expect(viewModel.selectedSummary?.sessionId == sessionId)
        let autoEvents = analytics.loggedEvents.filter { $0.name == "trip_summary_auto_presented_after_end" }
        #expect(autoEvents.count == 1)
    }

    @Test func presentTripSummaryShareSetsStateAndLogsAnalyticsOnce() async throws {
        let sessionId = UUID()
        let analytics = AnalyticsLoggingSpy()
        let viewModel = TravelLogViewModel(
            travelLogRepository: MockTravelLogRepository(),
            tripSessionRepository: MockTripSessionRepository(),
            gameInstanceRepository: MockGameInstanceRepository(),
            tripActivityEventRepository: MockTripActivityEventRepository(),
            authService: FirebaseAuthService(),
            analytics: analytics
        )
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }

        viewModel.presentTripSummaryShare(sessionId: sessionId, image: image, tripName: "Coastal Escape")

        #expect(viewModel.showTripSummaryShareSheet == true)
        #expect(viewModel.tripSummaryShareActivityItems.count == 1)
        #expect(viewModel.tripSummaryShareActivityItems.first is TripSummaryShareActivityItemSource)
        let shareEvents = analytics.loggedEvents.filter { $0.name == "trip_summary_shared" }
        #expect(shareEvents.count == 1)
        #expect(shareEvents[0].parameters?["session_id"] as? String == sessionId.uuidString)

        viewModel.clearTripSummaryShare()
        #expect(viewModel.showTripSummaryShareSheet == false)
        #expect(viewModel.tripSummaryShareActivityItems.isEmpty)
        #expect(analytics.loggedEvents.filter { $0.name == "trip_summary_shared" }.count == 1)
    }

    @Test func clearSelectionClearsTripSummaryShare() async throws {
        let viewModel = TravelLogViewModel(
            travelLogRepository: MockTravelLogRepository(),
            tripSessionRepository: MockTripSessionRepository(),
            gameInstanceRepository: MockGameInstanceRepository(),
            tripActivityEventRepository: MockTripActivityEventRepository(),
            authService: FirebaseAuthService(),
            analytics: AnalyticsLoggingSpy()
        )
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        viewModel.presentTripSummaryShare(sessionId: UUID(), image: image, tripName: "Trip")
        #expect(viewModel.showTripSummaryShareSheet == true)

        viewModel.clearSelection()
        #expect(viewModel.showTripSummaryShareSheet == false)
        #expect(viewModel.tripSummaryShareActivityItems.isEmpty)
    }

    @Test func flushPendingAutoRecapPresentsQueuedSummary() async throws {
        let sessionId = UUID()
        UserDefaults.standard.set([sessionId.uuidString], forKey: "tripEnd.pendingAutoRecapSessionIds")
        defer { UserDefaults.standard.removeObject(forKey: "tripEnd.pendingAutoRecapSessionIds") }

        let mockTrip = MockTripSessionRepository()
        mockTrip.seed(TripSession(
            id: sessionId,
            name: "Queued",
            status: .ended,
            createdAt: Date(),
            endedAt: Date(),
            participants: []
        ))
        let viewModel = TravelLogViewModel(
            travelLogRepository: MockTravelLogRepository(),
            tripSessionRepository: mockTrip,
            gameInstanceRepository: MockGameInstanceRepository(),
            tripActivityEventRepository: MockTripActivityEventRepository(),
            authService: FirebaseAuthService()
        )

        viewModel.flushPendingAutoRecapPresentations()

        #expect(viewModel.selectedSummary?.sessionId == sessionId)
    }

    private static func travelLogEntries(count: Int) -> [TravelLogEntry] {
        (0..<count).map { index in
            TravelLogEntry(
                id: "entry-\(index)",
                sessionId: UUID(),
                tripName: "Trip \(index)",
                endedAt: Date().addingTimeInterval(Double(-index * 60)),
                summary: "\(index) regions found",
                participantCount: 1,
                gameCount: 1,
                status: .ended
            )
        }
    }
}
