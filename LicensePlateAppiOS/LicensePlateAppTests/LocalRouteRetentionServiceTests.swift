//
//  LocalRouteRetentionServiceTests.swift
//  LicensePlateAppTests
//
//  COPPA v4 FR-105 (F-65): on-device route points are pruned 1095 days (v4 OD-12, 36 months
//  "like server") after their trip ends; an old trip's recap opens with no route section;
//  a voluntary leave drops the left trip's route (that trip never ends on this device);
//  hard sign-out and account deletion clear route points; policy row 13 ↔ constant parity.
//

import Foundation
import Combine
import CoreLocation
import SwiftData
import Testing
@testable import LicensePlateApp

@MainActor
struct LocalRouteRetentionServiceTests {

    /// Fixed clock for every fixture.
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 24 * 60 * 60

    private var cutoff: Date {
        LocalRouteRetentionPolicy.cutoff(now: now, windowDays: 1095)
    }

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

    private func makeService(ctx: ModelContext) -> (LocalRouteRetentionService, TripRoutePointRepository) {
        TripSessionRepository.shared.setModelContext(ctx)
        let routes = TripRoutePointRepository(modelContext: ctx)
        let service = LocalRouteRetentionService(
            tripSessionRepository: .shared,
            routePointRepository: routes,
            now: { [now] in now },
            windowDays: { 1095 }
        )
        return (service, routes)
    }

    @discardableResult
    private func insertTrip(
        _ ctx: ModelContext,
        status: TripSessionState,
        endedAt: Date?,
        name: String = "Trip"
    ) throws -> UUID {
        let id = UUID()
        ctx.insert(TripSessionEntity(
            id: id.uuidString,
            name: name,
            status: status.rawValue,
            createdAt: now.addingTimeInterval(-2000 * day),
            startedAt: now.addingTimeInterval(-2000 * day),
            endedAt: endedAt
        ))
        try ctx.save()
        return id
    }

    /// Four fixes several km apart, so the recap's endpoint trim leaves a drawable route.
    private func routeFixes(endingAt end: Date) -> [CLLocation] {
        let coords: [(Double, Double)] = [
            (39.7500, -104.9900), (39.7600, -104.9000), (39.7500, -104.8000), (39.7450, -104.7000)
        ]
        return coords.enumerated().map { index, coord in
            CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: coord.0, longitude: coord.1),
                altitude: 0,
                horizontalAccuracy: 10,
                verticalAccuracy: 5,
                timestamp: end.addingTimeInterval(Double(index - 4) * 600)
            )
        }
    }

    // MARK: - Pruning window

    @Test func tripEndedOutsideWindowIsPrunedAndInsideIsKept() throws {
        let ctx = try makeContext()
        let (service, routes) = makeService(ctx: ctx)
        let old = try insertTrip(ctx, status: .ended, endedAt: cutoff.addingTimeInterval(-30 * day))
        let recent = try insertTrip(ctx, status: .ended, endedAt: cutoff.addingTimeInterval(30 * day))
        try routes.append(points: routeFixes(endingAt: cutoff), tripSessionId: old)
        try routes.append(points: routeFixes(endingAt: now), tripSessionId: recent)

        #expect(service.pruneExpiredRoutePoints() == 1)

        #expect(try routes.points(tripSessionId: old).isEmpty)
        #expect(try routes.points(tripSessionId: recent).count == 4)
        // The trip itself survives; only its route goes.
        #expect(try TripSessionRepository.shared.session(byId: old) != nil)
    }

    @Test func boundaryTripIsKeptAndOneSecondPastIsPruned() throws {
        let ctx = try makeContext()
        let (service, routes) = makeService(ctx: ctx)
        let atCutoff = try insertTrip(ctx, status: .ended, endedAt: cutoff)
        let justPast = try insertTrip(ctx, status: .ended, endedAt: cutoff.addingTimeInterval(-1))
        try routes.append(points: routeFixes(endingAt: cutoff), tripSessionId: atCutoff)
        try routes.append(points: routeFixes(endingAt: cutoff), tripSessionId: justPast)

        #expect(service.pruneExpiredRoutePoints() == 1)

        // Server parity: `canonicalEndedAt < cutoff` — exactly 1095 days is still inside.
        #expect(try routes.points(tripSessionId: atCutoff).count == 4)
        #expect(try routes.points(tripSessionId: justPast).isEmpty)
    }

    @Test func cutoffIsExactly1095FixedDaysBeforeNow() {
        #expect(now.timeIntervalSince(cutoff) == 1095 * 86_400)
    }

    @Test func cancelledTripPastWindowIsPruned() throws {
        let ctx = try makeContext()
        let (service, routes) = makeService(ctx: ctx)
        let cancelled = try insertTrip(ctx, status: .cancelled, endedAt: cutoff.addingTimeInterval(-day))
        try routes.append(points: routeFixes(endingAt: cutoff), tripSessionId: cancelled)

        #expect(service.pruneExpiredRoutePoints() == 1)
        #expect(try routes.points(tripSessionId: cancelled).isEmpty)
    }

    @Test func liveAndNeverEndedTripsAreUntouched() throws {
        let ctx = try makeContext()
        let (service, routes) = makeService(ctx: ctx)
        // Active trip started years ago, no end date.
        let active = try insertTrip(ctx, status: .active, endedAt: nil)
        // Created-but-never-started trip.
        let created = try insertTrip(ctx, status: .created, endedAt: nil)
        // An ended-status row with no end date is not "ended long ago" — never a candidate.
        let endedNoDate = try insertTrip(ctx, status: .ended, endedAt: nil)
        // A live trip carrying a stale old endedAt is still live: status wins.
        let activeStaleEnd = try insertTrip(ctx, status: .active, endedAt: cutoff.addingTimeInterval(-400 * day))
        for id in [active, created, endedNoDate, activeStaleEnd] {
            try routes.append(points: routeFixes(endingAt: now), tripSessionId: id)
        }

        #expect(service.pruneExpiredRoutePoints() == 0)

        for id in [active, created, endedNoDate, activeStaleEnd] {
            #expect(try routes.points(tripSessionId: id).count == 4)
        }
    }

    @Test func secondRunIsANoOp() throws {
        let ctx = try makeContext()
        let (service, routes) = makeService(ctx: ctx)
        let old = try insertTrip(ctx, status: .ended, endedAt: cutoff.addingTimeInterval(-day))
        let recent = try insertTrip(ctx, status: .ended, endedAt: now.addingTimeInterval(-day))
        try routes.append(points: routeFixes(endingAt: cutoff), tripSessionId: old)
        try routes.append(points: routeFixes(endingAt: now), tripSessionId: recent)

        #expect(service.pruneExpiredRoutePoints() == 1)
        #expect(service.pruneExpiredRoutePoints() == 0)

        #expect(try routes.points(tripSessionId: old).isEmpty)
        #expect(try routes.points(tripSessionId: recent).count == 4)
    }

    @Test func oldTripWithNoPointsIsSkipped() throws {
        let ctx = try makeContext()
        let (service, routes) = makeService(ctx: ctx)
        let noRoute = try insertTrip(ctx, status: .ended, endedAt: cutoff.addingTimeInterval(-90 * day))

        #expect(try routes.points(tripSessionId: noRoute).isEmpty)
        #expect(service.pruneExpiredRoutePoints() == 0)
        #expect(try TripSessionRepository.shared.session(byId: noRoute) != nil)
    }

    @Test func emptyStoreIsANoOp() throws {
        let ctx = try makeContext()
        let (service, _) = makeService(ctx: ctx)
        #expect(service.pruneExpiredRoutePoints() == 0)
    }

    // MARK: - Regeneration (an old trip opens with no route section, no error)

    @Test func prunedOldTripOpensRecapWithNoRouteSectionAndNoError() throws {
        let ctx = try makeContext()
        TravelLogRepository.shared.setModelContext(ctx)
        TripSessionRepository.shared.setModelContext(ctx)
        GameInstanceRepository.shared.setModelContext(ctx)
        TripActivityEventRepository.shared.setModelContext(ctx)
        TripRoutePointRepository.shared.setModelContext(ctx)

        let old = try insertTrip(
            ctx,
            status: .ended,
            endedAt: cutoff.addingTimeInterval(-day),
            name: "Old Road Trip"
        )
        try TripRoutePointRepository.shared.append(
            points: routeFixes(endingAt: cutoff),
            tripSessionId: old
        )

        let viewModel = TravelLogViewModel(
            travelLogRepository: TravelLogRepository.shared,
            tripSessionRepository: TripSessionRepository.shared,
            gameInstanceRepository: GameInstanceRepository.shared,
            tripActivityEventRepository: TripActivityEventRepository.shared,
            authService: FirebaseAuthService()
        )

        // Before the pass: the recap path draws the route from the stored points.
        viewModel.openSummary(sessionId: old)
        #expect(viewModel.selectedSummary?.locationMetadata != nil)
        viewModel.clearSelection()

        let service = LocalRouteRetentionService(
            tripSessionRepository: .shared,
            routePointRepository: .shared,
            now: { [now] in now },
            windowDays: { 1095 }
        )
        #expect(service.pruneExpiredRoutePoints() == 1)

        // After: the same open path rebuilds the summary with no route and no error.
        viewModel.openSummary(sessionId: old)
        #expect(viewModel.summaryErrorMessage == nil)
        #expect(viewModel.selectedSummary?.sessionId == old)
        #expect(viewModel.selectedSummary?.tripName == "Old Road Trip")
        #expect(viewModel.selectedSummary?.locationMetadata == nil)
        let routeCoordinates = TripRouteSummaryBuilder.coordinates(
            from: viewModel.selectedSummary?.locationMetadata
        )
        #expect(routeCoordinates.isEmpty)
    }

    // MARK: - Voluntary leave drops the route (the left trip never ends locally)

    private final class IdleLocationSource: RouteTrackingLocationSource {
        var locationPublisher: AnyPublisher<CLLocation?, Never> { Empty().eraseToAnyPublisher() }
        var locationAuthorizationPublisher: AnyPublisher<Bool, Never> { Just(false).eraseToAnyPublisher() }
        var isAuthorizedForLocation: Bool { false }
        func beginRouteTracking() {}
        func endRouteTracking() {}
    }

    @Test func leavingAnActiveTripDeletesItsRoutePointsAndLeavesOthers() throws {
        let ctx = try makeContext()
        TripSessionRepository.shared.setModelContext(ctx)
        PendingTripLeaveRepository.shared.setModelContext(ctx)
        TripActivityEventRepository.shared.setModelContext(ctx)
        SyncQueueRepository.shared.setModelContext(ctx)
        let routes = TripRoutePointRepository(modelContext: ctx)
        let tracking = TripRouteTrackingService(locationSource: IdleLocationSource(), repository: routes)
        let recording = TripActivityEventRecordingService(
            tripActivityEventRepository: TripActivityEventRepository.shared,
            syncCoordinator: SyncCoordinator(repository: SyncQueueRepository.shared)
        )
        let participation = TripParticipationService(
            tripSessionRepository: TripSessionRepository.shared,
            tripActivityEventRecording: recording,
            pendingTripLeaveRepository: PendingTripLeaveRepository.shared,
            authService: nil,
            routeTracking: tracking
        )

        let left = UUID()
        try TripSessionRepository.shared.create(session: TripSession(
            id: left,
            name: "Shared",
            status: .active,
            createdAt: now,
            createdBy: "owner1",
            startedAt: now,
            participants: [
                TripParticipant(userId: "owner1", role: .owner, joinedAt: now),
                TripParticipant(userId: "joiner1", role: .member, joinedAt: now)
            ]
        ))
        let other = try insertTrip(ctx, status: .ended, endedAt: now.addingTimeInterval(-day))
        try routes.append(points: routeFixes(endingAt: now), tripSessionId: left)
        try routes.append(points: routeFixes(endingAt: now), tripSessionId: other)

        try participation.initiateLeaveTrip(sessionId: left, userId: "joiner1")

        // The left trip is still `active` here, so the launch pass would never reach it.
        #expect(try TripSessionRepository.shared.session(byId: left)?.status == .active)
        #expect(try routes.points(tripSessionId: left).isEmpty)
        #expect(try routes.points(tripSessionId: other).count == 4)
    }

    // MARK: - Sign-out and account deletion clear local route points

    @Test func hardSignOutPurgeClearsRoutePoints() throws {
        let ctx = try makeContext()
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
        defer { SyncCoordinator.shared.resumeProcessingAfterPurge() }

        let recent = try insertTrip(ctx, status: .ended, endedAt: now.addingTimeInterval(-day))
        let live = try insertTrip(ctx, status: .active, endedAt: nil)
        try TripRoutePointRepository.shared.append(points: routeFixes(endingAt: now), tripSessionId: recent)
        try TripRoutePointRepository.shared.append(points: routeFixes(endingAt: now), tripSessionId: live)

        try LocalUserDataPurgeService.shared.purgeAllLocalUserData(
            oldUserId: "route-purge-\(UUID().uuidString)"
        )

        #expect(try TripRoutePointRepository.shared.points(tripSessionId: recent).isEmpty)
        #expect(try TripRoutePointRepository.shared.points(tripSessionId: live).isEmpty)
    }

    /// Account deletion's local teardown runs the same purge as hard sign-out — pinned by
    /// source scan (the real call path needs Firebase Auth), like the FR-101(c) precedent.
    @Test func signOutAndAccountDeletionBothRunTheLocalPurge() throws {
        let authSource = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("LicensePlateApp/Services/FirebaseAuthService.swift"),
            encoding: .utf8
        )
        for function in ["func hardSignOutAndResetToGuest()", "func finalizeDeletedAccountLocally()"] {
            let start = try #require(authSource.range(of: function), "missing \(function)")
            let rest = authSource[start.upperBound...]
            // The body ends at the next member declaration or MARK, whichever comes first.
            let ends = ["\n    func ", "\n    private func ", "\n    // MARK"]
                .compactMap { rest.range(of: $0)?.lowerBound }
            let body = ends.min().map { rest[..<$0] } ?? rest
            #expect(
                body.contains("LocalUserDataPurgeService.shared.purgeAllLocalUserData("),
                "\(function) must run the local purge"
            )
        }
    }

    // MARK: - Policy ↔ constant parity (v3 FR-77 pattern)

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // LicensePlateAppTests
        .deletingLastPathComponent()   // LicensePlateAppiOS
        .deletingLastPathComponent()   // repo root

    @Test func windowConstantIs1095DaysAndMirrorsTheServerLocationAgingWindow() throws {
        #expect(LocalRouteRetentionPolicy.routePointRetentionDaysDefault == 1095)
        let server = try String(
            contentsOf: Self.repoRoot.appendingPathComponent(
                "LicensePlateAppiOS/functions/src/locationPayloadAging.ts"
            ),
            encoding: .utf8
        )
        #expect(server.contains(
            "LOCATION_PAYLOAD_RETENTION_DAYS_DEFAULT = \(LocalRouteRetentionPolicy.routePointRetentionDaysDefault);"
        ))
    }

    @Test func retentionPolicyRowStatesTheShippedWindow() throws {
        let policy = try String(
            contentsOf: Self.repoRoot.appendingPathComponent("RETENTION_POLICY.md"),
            encoding: .utf8
        )
        let row = try #require(
            policy.split(separator: "\n").first {
                $0.hasPrefix("|") && $0.contains("On-device trip route points")
            },
            "RETENTION_POLICY.md must have a schedule row for on-device route points"
        )
        // The policy speaks months; the pass counts days. 36 months ⇔ 1095 days is the
        // recorded equivalence (OD-3, v4 OD-12) — a change to either side must touch both.
        #expect(LocalRouteRetentionPolicy.routePointRetentionDaysDefault == 1095)
        #expect(row.contains("**36 months**"))
        #expect(row.contains("LocalRouteRetentionService"))
        #expect(row.contains("LocalUserDataPurgeService"))
        #expect(row.contains("ENFORCED"))
    }
}
