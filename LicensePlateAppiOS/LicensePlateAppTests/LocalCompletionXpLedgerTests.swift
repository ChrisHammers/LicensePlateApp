//
//  LocalCompletionXpLedgerTests.swift
//  LicensePlateAppTests
//
//  Local (unsynced) completion XP: `game_ended` / `game_completed` / `trip_ended` must reach the
//  displayed XP total the same way `region_found` does. Hermetic: every dependency injected.
//

import Foundation
import Testing
@testable import LicensePlateApp

@MainActor
struct LocalCompletionXpLedgerTests {

    private let rewards = ProgressionRewardsConfig.bundledDefault.xp

    // MARK: - Fixture

    private struct LocalTrip {
        var sessionId: UUID
        var gameId: UUID
        var events: MockTripActivityEventRepository
        var games: MockGameInstanceRepository
        var trips: MockTripSessionRepository
        var ledger: MockXpLedgerRepository
        var service: XpReconciliationService
    }

    private func makeLocalTrip(
        participantIds: [String],
        gameMode: GameMode = .competitive,
        tripStatus: TripSessionState = .active
    ) throws -> LocalTrip {
        let sessionId = UUID()
        let gameId = UUID()

        let participants = participantIds.enumerated().map { index, id in
            TripParticipant(userId: id, role: index == 0 ? .owner : .member, joinedAt: Date())
        }
        let session = TripSession(
            id: sessionId,
            name: "Local trip",
            status: tripStatus,
            createdAt: Date(),
            createdBy: participantIds.first,
            startedAt: Date(),
            participants: participants
        )

        let lpPayload = try JSONEncoder().encode(LicensePlateGameConfig())
        let game = GameInstance(
            id: gameId,
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: "license_plate"),
            commonConfig: CommonGameConfig(lifecycleState: .started, gameMode: gameMode),
            gameSpecificPayloadType: "license_plate",
            gameSpecificPayloadVersion: "1",
            gameSpecificPayloadData: lpPayload
        )

        let events = MockTripActivityEventRepository()
        let games = MockGameInstanceRepository()
        let trips = MockTripSessionRepository()
        let ledger = MockXpLedgerRepository()
        games.seed(game)
        trips.seed(session)

        let service = XpReconciliationService(
            xpLedger: ledger,
            resolutionRepo: DiscoveryResolutionRepository.shared,
            tripActivityEvents: events,
            gameRepository: games,
            tripSessionRepository: trips,
            rewardsConfig: StubRewardsConfigProvider(),
            clawbackHandler: { _ in }
        )

        return LocalTrip(
            sessionId: sessionId,
            gameId: gameId,
            events: events,
            games: games,
            trips: trips,
            ledger: ledger,
            service: service
        )
    }

    /// Appends the event to the local log and runs the same observer hop production uses
    /// (`ProgressionAppendObserverChain` -> `XpReconciliationService.handleCommittedActivityEvent`).
    private func commit(_ event: TripActivityEvent, into trip: LocalTrip) throws {
        try trip.events.append(event)
        trip.service.handleCommittedActivityEvent(event)
    }

    private func regionFound(
        id: String,
        trip: LocalTrip,
        regionId: String,
        participantId: String,
        at timestamp: Date
    ) -> TripActivityEvent {
        TripActivityEvent(
            id: id,
            sessionId: trip.sessionId,
            kind: .regionFound,
            timestamp: timestamp,
            actorId: participantId,
            payload: [
                TripActivityEventPayloadKey.regionId: regionId,
                TripActivityEventPayloadKey.gameInstanceId: trip.gameId.uuidString,
                TripActivityEventPayloadKey.participantId: participantId,
                TripActivityEventPayloadKey.inputMethod: FoundRegion.InputMethod.list.rawValue,
            ]
        )
    }

    private func gameEnded(id: String, trip: LocalTrip, at timestamp: Date) -> TripActivityEvent {
        TripActivityEvent(
            id: id,
            sessionId: trip.sessionId,
            kind: .gameEnded,
            timestamp: timestamp,
            actorId: nil,
            payload: [TripActivityEventPayloadKey.gameInstanceId: trip.gameId.uuidString]
        )
    }

    private func tripEnded(id: String, trip: LocalTrip, endedBy: String?, at timestamp: Date) -> TripActivityEvent {
        TripActivityEvent(
            id: id,
            sessionId: trip.sessionId,
            kind: .tripEnded,
            timestamp: timestamp,
            actorId: endedBy
        )
    }

    /// What the profile / license / toast actually render: server total + open provisional ledger.
    private func displayedXp(ledger: MockXpLedgerRepository, userId: String) throws -> Int {
        ProgressionDisplayTotalsResolver.resolve(
            userId: userId,
            ledgerEvents: try ledger.ledgerEvents(userId: userId),
            serverSnapshot: nil,
            verifiedGrantSum: nil,
            hasReceivedGrantSnapshot: false
        ).displayedTotalXp
    }

    /// Displayed XP from this trip's rows only.
    ///
    /// The ledger also carries **account-scoped** rows written under `XpLedgerGlobalScope` — the
    /// return-streak daily grant, and (FR-28e parity, owner 2026-08-15) the lifetime-first and
    /// first-of-day find bonuses. Those are deliberately not part of any single trip and
    /// `ProgressionLocalEngine` does not model them, so a comparison against the engine's
    /// session-scoped pending delta has to exclude them or it is comparing different things.
    private func sessionScopedDisplayedXp(
        ledger: MockXpLedgerRepository,
        userId: String,
        sessionId: UUID
    ) throws -> Int {
        let rows = try ledger.ledgerEvents(userId: userId).filter { $0.sessionId == sessionId }
        return ProgressionDisplayTotalsResolver.resolve(
            userId: userId,
            ledgerEvents: rows,
            serverSnapshot: nil,
            verifiedGrantSum: nil,
            hasReceivedGrantSnapshot: false
        ).displayedTotalXp
    }

    /// The two find bonuses one first-ever discovery on a fresh account mints locally.
    private var singleFirstFindBonuses: Int {
        rewards.lifetimeUniqueRegionFindBonusXp + rewards.firstFindOfDayBonusXp
    }

    // MARK: - Reproduction: local solo play, never synced

    @Test func localSoloPlayShowsFindAndCompletionXpWithoutServer() throws {
        let uid = "local-guest-1"
        let trip = try makeLocalTrip(participantIds: [uid])
        let t0 = Date()

        try commit(regionFound(id: "find-1", trip: trip, regionId: "us-tx", participantId: uid, at: t0), into: trip)
        try commit(gameEnded(id: "game-end-1", trip: trip, at: t0.addingTimeInterval(1)), into: trip)
        try commit(tripEnded(id: "trip-end-1", trip: trip, endedBy: uid, at: t0.addingTimeInterval(2)), into: trip)

        let expected = rewards.baseDiscoveryXp
            // Owner parity ruling 2026-08-15: the lifetime-first (+20) and first-of-day (+10)
            // bonuses are no longer server-only, so unsynced local play earns them too.
            + singleFirstFindBonuses
            + rewards.gameEndedBonusXp
            + rewards.competitiveFirstPlaceFinishBonusXp
            + rewards.tripEndedBonusXp
            + rewards.tripParticipationBonusXp
            + rewards.tripCompetitiveFirstPlaceBonusXp

        #expect(try displayedXp(ledger: trip.ledger, userId: uid) == expected)
    }

    @Test func localCompletionXpMatchesProgressionLocalEnginePending() throws {
        let uid = "local-guest-1"
        let trip = try makeLocalTrip(participantIds: [uid])
        let t0 = Date()

        try commit(regionFound(id: "find-1", trip: trip, regionId: "us-tx", participantId: uid, at: t0), into: trip)
        try commit(gameEnded(id: "game-end-1", trip: trip, at: t0.addingTimeInterval(1)), into: trip)
        try commit(tripEnded(id: "trip-end-1", trip: trip, endedBy: uid, at: t0.addingTimeInterval(2)), into: trip)

        let game = try #require(try trip.games.instance(byId: trip.gameId))
        let enginePending = ProgressionLocalEngine.pendingDeltaForSession(
            sortedSessionEvents: try trip.events.events(sessionId: trip.sessionId, limit: nil),
            rosterUserIds: [uid],
            subjectUserId: uid,
            serverAppliedEventIds: [],
            gamesById: [trip.gameId: game.progressionGameSnapshot],
            rewards: ProgressionRewardsConfig.bundledDefault
        )

        // The two local projections of the same offline play must agree on this trip's XP.
        #expect(
            try sessionScopedDisplayedXp(ledger: trip.ledger, userId: uid, sessionId: trip.sessionId)
                == enginePending.totalXp
        )
    }

    @Test func fullClearAwardsGameCompletedBonusLocally() throws {
        let uid = "local-guest-1"
        let trip = try makeLocalTrip(participantIds: [uid])
        let t0 = Date()

        let completed = TripActivityEvent(
            id: "game-complete-1",
            sessionId: trip.sessionId,
            kind: .gameCompleted,
            timestamp: t0,
            payload: [TripActivityEventPayloadKey.gameInstanceId: trip.gameId.uuidString]
        )
        try commit(completed, into: trip)

        let rows = try trip.ledger.ledgerEvents(userId: uid)
        #expect(rows.contains { $0.reasonCode == .gameFullClear && $0.xpDelta == rewards.gameFullClearBonusXp })
    }

    // MARK: - Idempotency and settlement

    @Test func replayingTheSameCompletionEventDoesNotDoubleAward() throws {
        let uid = "local-guest-1"
        let trip = try makeLocalTrip(participantIds: [uid])
        let t0 = Date()

        let end = gameEnded(id: "game-end-1", trip: trip, at: t0)
        try commit(end, into: trip)
        trip.service.handleCommittedActivityEvent(end)
        trip.service.handleCommittedActivityEvent(end)

        let gameEndedRows = try trip.ledger.ledgerEvents(userId: uid).filter { $0.reasonCode == .gameEnded }
        #expect(gameEndedRows.count == 1)
    }

    @Test func serverAppliedCompletionEventStopsInflatingDisplayedTotal() throws {
        let uid = "local-guest-1"
        let trip = try makeLocalTrip(participantIds: [uid])
        let t0 = Date()

        try commit(gameEnded(id: "game-end-1", trip: trip, at: t0), into: trip)

        let serverApplied = UserProgressionSnapshot(
            totalXp: rewards.gameEndedBonusXp + rewards.competitiveFirstPlaceFinishBonusXp,
            acceptedRegionFindCount: 0,
            competitiveFirstPlaceFinishes: 1,
            everCompetitiveFirstPlace: true,
            lastUpdatedAt: Date(),
            appliedProgressionEventIds: ["game-end-1"],
            appliedProgressionScopeKeys: []
        )
        let totals = ProgressionDisplayTotalsResolver.resolve(
            userId: uid,
            ledgerEvents: try trip.ledger.ledgerEvents(userId: uid),
            serverSnapshot: serverApplied,
            verifiedGrantSum: nil,
            hasReceivedGrantSnapshot: false
        )

        // Once the server owns the event the local rows must stop adding on top of it.
        #expect(totals.openProvisionalXp == 0)
        #expect(totals.displayedTotalXp == serverApplied.totalXp)
    }

    // MARK: - Toast: the owner-reported symptom, end to end

    /// Owner field report: on a sync-held child account the discovery toast pops but the trip-ended
    /// toast never does. Drives the real `XpGainToastService` over the rows the real writer produced.
    @Test func heldChildEndingTripLocallyGetsCompletionToastThenNoDuplicateFromServerGrant() throws {
        let uid = "child-awaiting-consent"
        let trip = try makeLocalTrip(participantIds: [uid], gameMode: .collaborative)
        let t0 = Date()

        // Sync is held: no server progression snapshot and no grants have ever arrived.
        let remote = StubToastRemoteReader()
        remote.hasReceivedInitialSnapshot = false

        let service = XpGainToastService(
            xpLedger: trip.ledger,
            remoteReader: remote,
            wiresLiveUpdates: false
        )
        service.configure(userId: uid)
        service.performImmediateRefresh()
        #expect(service.presentation == nil)

        try commit(regionFound(id: "find-1", trip: trip, regionId: "us-tx", participantId: uid, at: t0), into: trip)
        try commit(tripEnded(id: "trip-end-1", trip: trip, endedBy: uid, at: t0.addingTimeInterval(1)), into: trip)
        service.performImmediateRefresh()

        let presentation = try #require(service.presentation)
        let groupIds = Set(presentation.lines.map(\.id))
        // The discovery toast always worked; these two are what the owner never saw.
        #expect(groupIds.contains("discovery"))
        #expect(groupIds.contains("trip_ended"))
        #expect(groupIds.contains("trip_participation"))
        // Owner parity ruling 2026-08-15: a held child earns the find bonuses too, so their
        // toast groups fire without any server involvement.
        #expect(groupIds.contains("lifetime_unique"))
        #expect(groupIds.contains("first_of_day"))

        let expectedBurst = rewards.baseDiscoveryXp
            + singleFirstFindBonuses
            + rewards.tripEndedBonusXp
            + rewards.tripParticipationBonusXp
        #expect(presentation.totalXp == expectedBurst)

        // Consent lands, sync drains, and the server grants the same trip_ended event.
        remote.hasReceivedInitialSnapshot = true
        remote.grants = [
            UserXpGrant(
                grantId: "g-trip-ended",
                amount: rewards.tripEndedBonusXp,
                reason: UserXpGrantReason.tripEnded.rawValue,
                sourceType: "activity_event",
                sourceId: "trip-end-1",
                idempotencyKey: "trip_ended|v1|\(uid)|\(trip.sessionId.uuidString)"
            ),
            UserXpGrant(
                grantId: "g-trip-participation",
                amount: rewards.tripParticipationBonusXp,
                reason: UserXpGrantReason.tripParticipation.rawValue,
                sourceType: "activity_event",
                sourceId: "trip-end-1",
                idempotencyKey: "trip_participation|v1|\(uid)|\(trip.sessionId.uuidString)"
            ),
        ]
        service.performImmediateRefresh()

        // Same awards already toasted locally — the burst must not grow.
        #expect(service.presentation?.totalXp == expectedBurst)
    }

    @Test func grantForAnEventThisDeviceNeverRecordedStillToasts() throws {
        let uid = "peer-1"
        let trip = try makeLocalTrip(participantIds: [uid], gameMode: .collaborative)

        let remote = StubToastRemoteReader()
        remote.hasReceivedInitialSnapshot = false
        let service = XpGainToastService(
            xpLedger: trip.ledger,
            remoteReader: remote,
            wiresLiveUpdates: false
        )
        service.configure(userId: uid)
        service.performImmediateRefresh()

        try commit(tripEnded(id: "trip-end-1", trip: trip, endedBy: uid, at: Date()), into: trip)
        service.performImmediateRefresh()
        let afterLocal = try #require(service.presentation).totalXp

        // A peer's game ended on their device; this device has no local row for it.
        remote.hasReceivedInitialSnapshot = true
        remote.grants = [
            UserXpGrant(
                grantId: "g-peer-game-ended",
                amount: rewards.gameEndedBonusXp,
                reason: UserXpGrantReason.gameEnded.rawValue,
                sourceType: "activity_event",
                sourceId: "game-ended-on-another-device",
                idempotencyKey: "game_ended|v1|\(uid)|peer"
            )
        ]
        service.performImmediateRefresh()

        #expect(service.presentation?.totalXp == afterLocal + rewards.gameEndedBonusXp)
    }

    // MARK: - Toast: local row and its later server grant are one award, not two

    @Test func serverGrantMirroringALocalCompletionRowSharesItsAwardKey() throws {
        let uid = "local-guest-1"
        let trip = try makeLocalTrip(participantIds: [uid])

        try commit(gameEnded(id: "game-end-1", trip: trip, at: Date()), into: trip)

        let localRow = try #require(
            try trip.ledger.ledgerEvents(userId: uid).first { $0.reasonCode == .gameEnded }
        )
        let mirroringGrant = UserXpGrant(
            grantId: "grant-1",
            amount: rewards.gameEndedBonusXp,
            reason: UserXpGrantReason.gameEnded.rawValue,
            sourceType: "activity_event",
            sourceId: "game-end-1",
            idempotencyKey: "game_ended|v1|\(uid)|\(trip.gameId.uuidString)"
        )

        #expect(XpGainToastEligibility.localAwardKey(for: localRow)
            == XpGainToastEligibility.localAwardKey(for: mirroringGrant))
    }

    @Test func grantForADifferentAwardOrEventKeepsItsOwnToast() throws {
        let uid = "local-guest-1"
        let trip = try makeLocalTrip(participantIds: [uid])

        try commit(gameEnded(id: "game-end-1", trip: trip, at: Date()), into: trip)

        let localRow = try #require(
            try trip.ledger.ledgerEvents(userId: uid).first { $0.reasonCode == .gameEnded }
        )
        let localKey = XpGainToastEligibility.localAwardKey(for: localRow)

        // Same event, different component (placement) — must still toast.
        let placementGrant = UserXpGrant(
            grantId: "grant-2",
            amount: rewards.competitiveFirstPlaceFinishBonusXp,
            reason: UserXpGrantReason.competitiveFirstPlaceFinish.rawValue,
            sourceType: "activity_event",
            sourceId: "game-end-1",
            idempotencyKey: "competitive_place|1"
        )
        // Same award, different event (a peer's game this device never recorded) — must still toast.
        let peerGrant = UserXpGrant(
            grantId: "grant-3",
            amount: rewards.gameEndedBonusXp,
            reason: UserXpGrantReason.gameEnded.rawValue,
            sourceType: "activity_event",
            sourceId: "game-end-on-another-device",
            idempotencyKey: "game_ended|v1|other"
        )

        #expect(localKey != XpGainToastEligibility.localAwardKey(for: placementGrant))
        #expect(localKey != XpGainToastEligibility.localAwardKey(for: peerGrant))
    }

    @Test func discoveryRowsAreNotTreatedAsCompletionAwards() throws {
        let uid = "local-guest-1"
        let trip = try makeLocalTrip(participantIds: [uid])

        try commit(regionFound(id: "find-1", trip: trip, regionId: "us-tx", participantId: uid, at: Date()), into: trip)

        let discoveryRow = try #require(
            try trip.ledger.ledgerEvents(userId: uid).first { $0.grantKind == .provisionalDiscoveryXp }
        )
        // Discovery keeps its existing blanket remote-suppression rule; no per-award key.
        #expect(XpGainToastEligibility.localAwardKey(for: discoveryRow) == nil)
    }

    // MARK: - Roster / attribution parity with the server

    @Test func nonRosterSubjectGetsNoCompletionXp() throws {
        let owner = "owner-1"
        let stranger = "not-in-this-trip"
        let trip = try makeLocalTrip(participantIds: [owner])

        try commit(gameEnded(id: "game-end-1", trip: trip, at: Date()), into: trip)

        #expect(try trip.ledger.ledgerEvents(userId: stranger).isEmpty)
        #expect(try !trip.ledger.ledgerEvents(userId: owner).isEmpty)
    }

    @Test func tripParticipationBonusOnlyForParticipantsWhoFound() throws {
        let finder = "finder-1"
        let idler = "idler-2"
        let trip = try makeLocalTrip(participantIds: [finder, idler], gameMode: .collaborative)
        let t0 = Date()

        try commit(regionFound(id: "find-1", trip: trip, regionId: "us-tx", participantId: finder, at: t0), into: trip)
        try commit(tripEnded(id: "trip-end-1", trip: trip, endedBy: finder, at: t0.addingTimeInterval(1)), into: trip)

        let finderRows = try trip.ledger.ledgerEvents(userId: finder)
        let idlerRows = try trip.ledger.ledgerEvents(userId: idler)

        #expect(finderRows.contains { $0.reasonCode == .tripParticipation })
        #expect(!idlerRows.contains { $0.reasonCode == .tripParticipation })
        // Both are on the roster, so both still get the trip-ended bonus.
        #expect(finderRows.contains { $0.reasonCode == .tripEnded })
        #expect(idlerRows.contains { $0.reasonCode == .tripEnded })
    }

    @Test func cancelledTripAwardsNoCompletionXp() throws {
        let uid = "local-guest-1"
        let trip = try makeLocalTrip(participantIds: [uid], tripStatus: .cancelled)

        try commit(gameEnded(id: "game-end-1", trip: trip, at: Date()), into: trip)

        #expect(try trip.ledger.ledgerEvents(userId: uid).isEmpty)
    }

    // MARK: - Competitive placement parity

    @Test func competitivePlacementsAwardedLocallyByContribution() throws {
        let winner = "winner-1"
        let runnerUp = "runner-2"
        let trip = try makeLocalTrip(participantIds: [winner, runnerUp], gameMode: .competitive)
        let t0 = Date()

        try commit(regionFound(id: "f1", trip: trip, regionId: "us-tx", participantId: winner, at: t0), into: trip)
        try commit(regionFound(id: "f2", trip: trip, regionId: "us-ca", participantId: winner, at: t0.addingTimeInterval(1)), into: trip)
        try commit(regionFound(id: "f3", trip: trip, regionId: "us-ny", participantId: runnerUp, at: t0.addingTimeInterval(2)), into: trip)
        try commit(gameEnded(id: "game-end-1", trip: trip, at: t0.addingTimeInterval(3)), into: trip)

        let winnerRows = try trip.ledger.ledgerEvents(userId: winner)
        let runnerRows = try trip.ledger.ledgerEvents(userId: runnerUp)

        #expect(winnerRows.contains { $0.reasonCode == .competitiveFirstFinder || $0.reasonCode == .discoveryClaimPendingResolution })
        #expect(winnerRows.first { $0.reasonCode == .gameEnded }?.xpDelta == rewards.gameEndedBonusXp)
        #expect(runnerRows.first { $0.reasonCode == .gameEnded }?.xpDelta == rewards.gameEndedBonusXp)

        let winnerPlacement = winnerRows.first { $0.reasonCode == .competitiveFirstPlaceFinish }
        let runnerPlacement = runnerRows.first { $0.reasonCode == .competitiveSecondPlace }
        #expect(winnerPlacement?.xpDelta == rewards.competitiveFirstPlaceFinishBonusXp)
        #expect(runnerPlacement?.xpDelta == rewards.competitiveSecondPlaceFinishBonusXp)
    }
}

// MARK: - Stubs

private struct StubRewardsConfigProvider: ProgressionRewardsConfigProviding {
    var current: ProgressionRewardsConfig { .bundledDefault }
    func refresh(presentationOverrideJSON: String?) {}
}

@MainActor
private final class StubToastRemoteReader: XpGainToastRemoteReading {
    var grants: [UserXpGrant] = []
    var hasReceivedInitialSnapshot = false
}
