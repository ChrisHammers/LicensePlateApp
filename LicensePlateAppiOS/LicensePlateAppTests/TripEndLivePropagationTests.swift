//
//  TripEndLivePropagationTests.swift
//  LicensePlateAppTests
//
//  Trip-end propagation regression (owner device pass 2026-09-07).
//
//  Two halves of the same repro:
//  (1) A ended a live trip; D had the trip screen open and saw it, C was on HOME and did not —
//      canonical listeners were only ever started for an OPENED trip, so a device that had not
//      opened one this process heard nothing. `LiveTripListenerEligibility` is the rule for which
//      locally-held sessions a device must listen to regardless of what is on screen.
//  (2) The trip-end XP looked granted twice. `applyRemoteTripEnded` used the AUTHORING path
//      (`endGame`), minting a duplicate local `game_ended` with a fresh id on every peer.
//

import Foundation
import SwiftData
import Testing
@testable import LicensePlateApp

@MainActor
struct TripEndLivePropagationTests {

    // MARK: - Fixtures

    private let me = "user-me"
    private let owner = "user-owner"

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [config]
        )
    }

    private func makeSession(
        id: UUID = UUID(),
        status: TripSessionState,
        createdBy: String?,
        participants: [TripParticipant]
    ) -> TripSession {
        TripSession(
            id: id,
            name: "Road Trip",
            status: status,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            createdBy: createdBy,
            startedAt: status == .active ? Date(timeIntervalSince1970: 1_700_000_100) : nil,
            participants: participants
        )
    }

    private func makeGame(
        id: UUID = UUID(),
        sessionId: UUID,
        lifecycleState: GameInstanceState = .started,
        endedAt: Date? = nil
    ) -> GameInstance {
        GameInstance(
            id: id,
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            endedAt: endedAt,
            ruleSet: GameRuleSet(gameDefinitionId: GameType.licensePlate.rawValue),
            commonConfig: CommonGameConfig(
                lifecycleState: lifecycleState,
                configLocked: true,
                configLockReason: .gameStarted
            )
        )
    }

    /// Real services over mock repositories: the point of these tests is what gets WRITTEN.
    private func makeLifecycleStack() -> (
        sessions: MockTripSessionRepository,
        games: MockGameInstanceRepository,
        events: MockTripActivityEventRepository,
        sync: MockSyncCoordinator,
        service: TripSessionLifecycleService
    ) {
        let sessions = MockTripSessionRepository()
        let games = MockGameInstanceRepository()
        let events = MockTripActivityEventRepository()
        let sync = MockSyncCoordinator()
        let recording = TripActivityEventRecordingService(
            tripActivityEventRepository: events,
            syncCoordinator: sync
        )
        let gameLifecycle = GameInstanceLifecycleService(
            tripSessionRepository: sessions,
            gameInstanceRepository: games,
            tripActivityEventRepository: events,
            tripActivityEventRecording: recording
        )
        let service = TripSessionLifecycleService(
            tripSessionRepository: sessions,
            gameInstanceRepository: games,
            tripActivityEventRepository: events,
            tripActivityEventRecording: recording,
            gameInstanceLifecycleService: gameLifecycle
        )
        return (sessions, games, events, sync, service)
    }

    // MARK: - (1) Which sessions this device must listen to

    @Test func listensToEveryLiveSessionTheUserIsOnRegardlessOfWhatIsOnScreen() {
        let joinedActive = makeSession(
            status: .active,
            createdBy: owner,
            participants: [TripParticipant(userId: owner, role: .owner), TripParticipant(userId: me)]
        )
        let ownedCreated = makeSession(
            status: .created,
            createdBy: me,
            participants: [TripParticipant(userId: me, role: .owner)]
        )

        let ids = LiveTripListenerEligibility.sessionIdsNeedingListeners(
            sessions: [joinedActive, ownedCreated],
            userId: me,
            authenticatedUserId: me,
            isCloudSyncHeld: false
        )

        #expect(Set(ids) == Set([joinedActive.id, ownedCreated.id]))
    }

    @Test func doesNotListenToSessionsThatAreNoLongerLive() {
        let ended = makeSession(
            status: .ended,
            createdBy: owner,
            participants: [TripParticipant(userId: owner, role: .owner), TripParticipant(userId: me)]
        )
        let cancelled = makeSession(
            status: .cancelled,
            createdBy: owner,
            participants: [TripParticipant(userId: owner, role: .owner), TripParticipant(userId: me)]
        )

        let ids = LiveTripListenerEligibility.sessionIdsNeedingListeners(
            sessions: [ended, cancelled],
            userId: me,
            authenticatedUserId: me,
            isCloudSyncHeld: false
        )

        #expect(ids.isEmpty)
    }

    @Test func doesNotListenToSessionsTheUserIsNotOnOrHasLeft() {
        let notMine = makeSession(
            status: .active,
            createdBy: owner,
            participants: [TripParticipant(userId: owner, role: .owner), TripParticipant(userId: "someone-else")]
        )
        let departed = makeSession(
            status: .active,
            createdBy: owner,
            participants: [
                TripParticipant(userId: owner, role: .owner),
                TripParticipant(userId: me, role: .member, joinedAt: Date(), leftAt: Date()),
            ]
        )

        let ids = LiveTripListenerEligibility.sessionIdsNeedingListeners(
            sessions: [notMine, departed],
            userId: me,
            authenticatedUserId: me,
            isCloudSyncHeld: false
        )

        #expect(ids.isEmpty)
    }

    /// FR-28: an unconsented child's gameplay cloud traffic is paused; that includes reads.
    @Test func listensToNothingWhileTheChildCloudSyncHoldIsOn() {
        let live = makeSession(
            status: .active,
            createdBy: owner,
            participants: [TripParticipant(userId: owner, role: .owner), TripParticipant(userId: me)]
        )

        let ids = LiveTripListenerEligibility.sessionIdsNeedingListeners(
            sessions: [live],
            userId: me,
            authenticatedUserId: me,
            isCloudSyncHeld: true
        )

        #expect(ids.isEmpty)
    }

    /// §3.1.1 item 7: `purgeSocialStateForDetachedIdentity` stops these listeners on purpose;
    /// the launch/foreground re-assert must not put them back.
    @Test func listensToNothingForADetachedIdentity() {
        let live = makeSession(
            status: .active,
            createdBy: owner,
            participants: [TripParticipant(userId: owner, role: .owner), TripParticipant(userId: me)]
        )

        let ids = LiveTripListenerEligibility.sessionIdsNeedingListeners(
            sessions: [live],
            userId: me,
            authenticatedUserId: me,
            isCloudSyncHeld: false,
            isIdentityDetached: true
        )

        #expect(ids.isEmpty)
    }

    /// A local-only play identity (no Firebase uid) has no cloud document to listen to, and a
    /// listener started under a different identity would mis-attribute an FR-69 eviction.
    @Test func listensToNothingWhenThePlayIdentityIsNotTheAuthenticatedOne() {
        let live = makeSession(
            status: .active,
            createdBy: me,
            participants: [TripParticipant(userId: me, role: .owner)]
        )

        #expect(LiveTripListenerEligibility.sessionIdsNeedingListeners(
            sessions: [live],
            userId: me,
            authenticatedUserId: nil,
            isCloudSyncHeld: false
        ).isEmpty)

        #expect(LiveTripListenerEligibility.sessionIdsNeedingListeners(
            sessions: [live],
            userId: me,
            authenticatedUserId: "retired-uid",
            isCloudSyncHeld: false
        ).isEmpty)

        #expect(LiveTripListenerEligibility.sessionIdsNeedingListeners(
            sessions: [live],
            userId: nil,
            authenticatedUserId: nil,
            isCloudSyncHeld: false
        ).isEmpty)
    }

    /// End-to-end over the real repository: what `loadActiveSessions` returns is what the
    /// launch/foreground pass listens to.
    @Test func repositoryBackedSelectionCoversJoinedTripsNeverOpenedOnThisDevice() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let repo = TripSessionRepository.shared
        repo.setModelContext(context)
        PendingTripLeaveRepository.shared.setModelContext(context)

        let joined = makeSession(
            status: .active,
            createdBy: owner,
            participants: [TripParticipant(userId: owner, role: .owner), TripParticipant(userId: me)]
        )
        let mineCreated = makeSession(
            status: .created,
            createdBy: me,
            participants: [TripParticipant(userId: me, role: .owner)]
        )
        let alreadyEnded = makeSession(
            status: .ended,
            createdBy: owner,
            participants: [TripParticipant(userId: owner, role: .owner), TripParticipant(userId: me)]
        )
        let strangers = makeSession(
            status: .active,
            createdBy: owner,
            participants: [TripParticipant(userId: owner, role: .owner)]
        )
        for session in [joined, mineCreated, alreadyEnded, strangers] {
            try repo.create(session: session)
        }

        let ids = LiveTripListenerEligibility.sessionIdsNeedingListeners(
            sessions: try repo.loadActiveSessions(userId: me),
            userId: me,
            authenticatedUserId: me,
            isCloudSyncHeld: false
        )

        #expect(Set(ids) == Set([joined.id, mineCreated.id]))
    }

    // MARK: - (2) A remote trip end grants trip-end XP exactly once

    @Test func applyingARemoteTripEndAuthorsNoLocalGameplayEvents() throws {
        let stack = makeLifecycleStack()
        let sessionId = UUID()
        let gameId = UUID()
        stack.sessions.seed(makeSession(
            id: sessionId,
            status: .active,
            createdBy: owner,
            participants: [TripParticipant(userId: owner, role: .owner), TripParticipant(userId: me)]
        ))
        stack.games.seed(makeGame(id: gameId, sessionId: sessionId))

        // The owner's canonical `trip_ended`, already imported by the activity_events listener.
        try stack.events.appendIfAbsent(TripActivityEvent(
            id: "owner-trip-ended",
            sessionId: sessionId,
            kind: .tripEnded,
            timestamp: Date(timeIntervalSince1970: 1_700_000_500),
            actorId: owner
        ))
        let importedIds = Set(stack.events.appendedEvents().map(\.id))

        let applied = try stack.service.applyRemoteTripEnded(
            sessionId: sessionId,
            endedBy: owner,
            endedAt: Date(timeIntervalSince1970: 1_700_000_500)
        )

        #expect(applied)
        // Nothing new was authored — no duplicate `game_ended` under a fresh id...
        let after = stack.events.appendedEvents()
        #expect(Set(after.map(\.id)) == importedIds)
        #expect(after.filter { $0.kind == .gameEnded }.isEmpty)
        // ...and nothing was queued for upload from a device that did not end the trip.
        #expect(stack.sync.enqueueEventIds.isEmpty)
    }

    @Test func applyingARemoteTripEndStillClosesTheTripAndItsGames() throws {
        let stack = makeLifecycleStack()
        let sessionId = UUID()
        let gameId = UUID()
        let endedAt = Date(timeIntervalSince1970: 1_700_000_500)
        stack.sessions.seed(makeSession(
            id: sessionId,
            status: .active,
            createdBy: owner,
            participants: [TripParticipant(userId: owner, role: .owner), TripParticipant(userId: me)]
        ))
        stack.games.seed(makeGame(id: gameId, sessionId: sessionId))

        _ = try stack.service.applyRemoteTripEnded(sessionId: sessionId, endedBy: owner, endedAt: endedAt)

        let session = try stack.sessions.session(byId: sessionId)
        #expect(session?.status == .ended)
        #expect(session?.endedAt == endedAt)
        #expect(session?.endedBy == owner)

        let game = try stack.games.instance(byId: gameId)
        #expect(game?.commonConfig.lifecycleState == .ended)
        #expect(game?.endedAt == endedAt)
    }

    @Test func applyingARemoteTripEndTwiceIsANoOpTheSecondTime() throws {
        let stack = makeLifecycleStack()
        let sessionId = UUID()
        stack.sessions.seed(makeSession(
            id: sessionId,
            status: .active,
            createdBy: owner,
            participants: [TripParticipant(userId: owner, role: .owner), TripParticipant(userId: me)]
        ))
        stack.games.seed(makeGame(sessionId: sessionId))

        let first = try stack.service.applyRemoteTripEnded(sessionId: sessionId, endedBy: owner, endedAt: Date())
        let second = try stack.service.applyRemoteTripEnded(sessionId: sessionId, endedBy: owner, endedAt: Date())

        #expect(first)
        #expect(!second)
        #expect(stack.events.appendedEvents().isEmpty)
    }

    /// `TripEndRecapHost` runs this on appear and on every foreground; it must not author either.
    @Test func reconcilingAStoredRemoteTripEndAuthorsNoLocalGameplayEvents() throws {
        let stack = makeLifecycleStack()
        let sessionId = UUID()
        stack.sessions.seed(makeSession(
            id: sessionId,
            status: .active,
            createdBy: owner,
            participants: [TripParticipant(userId: owner, role: .owner), TripParticipant(userId: me)]
        ))
        stack.games.seed(makeGame(sessionId: sessionId))
        try stack.events.appendIfAbsent(TripActivityEvent(
            id: "owner-trip-ended",
            sessionId: sessionId,
            kind: .tripEnded,
            timestamp: Date(timeIntervalSince1970: 1_700_000_500),
            actorId: owner
        ))

        let infos = try stack.service.reconcileRemoteTripEndedFromEventLog(userId: me)

        #expect(infos.map(\.sessionId) == [sessionId])
        #expect(stack.events.appendedEvents().map(\.id) == ["owner-trip-ended"])
        #expect(stack.sync.enqueueEventIds.isEmpty)
    }

    /// Parity guard: the OWNER's own end is still the authoring path and still emits both events.
    @Test func theOwnersOwnEndStillAuthorsGameEndedAndTripEnded() throws {
        let stack = makeLifecycleStack()
        let sessionId = UUID()
        let gameId = UUID()
        stack.sessions.seed(makeSession(
            id: sessionId,
            status: .active,
            createdBy: owner,
            participants: [TripParticipant(userId: owner, role: .owner), TripParticipant(userId: me)]
        ))
        stack.games.seed(makeGame(id: gameId, sessionId: sessionId))

        try stack.service.endTrip(sessionId: sessionId, endedBy: owner)

        let authored = stack.events.appendedEvents()
        #expect(authored.contains { $0.kind == .tripEnded && $0.actorId == owner })
        #expect(authored.contains {
            $0.kind == .gameEnded
                && $0.payload?[TripActivityEventPayloadKey.gameInstanceId] == gameId.uuidString
        })
        #expect(stack.sync.enqueueEventIds.count == authored.count)
    }

    // MARK: - Remote game close

    @Test func remoteGameCloseIsIdempotentAndKeepsTheFirstEndTimestamp() throws {
        let sessions = MockTripSessionRepository()
        let games = MockGameInstanceRepository()
        let events = MockTripActivityEventRepository()
        let sync = MockSyncCoordinator()
        let service = GameInstanceLifecycleService(
            tripSessionRepository: sessions,
            gameInstanceRepository: games,
            tripActivityEventRepository: events,
            tripActivityEventRecording: TripActivityEventRecordingService(
                tripActivityEventRepository: events,
                syncCoordinator: sync
            )
        )
        let sessionId = UUID()
        let gameId = UUID()
        let first = Date(timeIntervalSince1970: 1_700_000_500)
        games.seed(makeGame(id: gameId, sessionId: sessionId))

        let changed = try service.applyRemoteGameEnded(gameInstanceId: gameId, endedAt: first)
        let again = try service.applyRemoteGameEnded(
            gameInstanceId: gameId,
            endedAt: Date(timeIntervalSince1970: 1_700_009_999)
        )

        #expect(changed)
        #expect(!again)
        #expect(try games.instance(byId: gameId)?.endedAt == first)
        #expect(events.appendedEvents().isEmpty)
        #expect(sync.enqueueEventIds.isEmpty)
    }

    @Test func remoteGameCloseIgnoresAGameThisDeviceDoesNotHave() throws {
        let sessions = MockTripSessionRepository()
        let games = MockGameInstanceRepository()
        let events = MockTripActivityEventRepository()
        let service = GameInstanceLifecycleService(
            tripSessionRepository: sessions,
            gameInstanceRepository: games,
            tripActivityEventRepository: events,
            tripActivityEventRecording: TripActivityEventRecordingService(
                tripActivityEventRepository: events,
                syncCoordinator: MockSyncCoordinator()
            )
        )

        #expect(try service.applyRemoteGameEnded(gameInstanceId: UUID(), endedAt: Date()) == false)
    }
}
