//
//  AccountTripDiscoveryTests.swift
//  LicensePlateAppTests
//
//  §3.1.1 item 19 — account-scoped trip discovery. Every trip the account created or joined
//  follows it to any device it signs into.
//
//  Four groups, all Firebase-free:
//   1. the FAIL-CLOSED gate (one case per predicate, including the unresolved child posture
//      that FR-28's `isCloudSyncHeld` alone cannot cover on a fresh device);
//   2. the planner — absent-only import, no listeners on ended trips, cancelled never
//      imported, publish-race retry, and the in-flight guard against the cache-then-server
//      snapshot pair;
//   3. the absent-only import over the existing repository fakes: a discovered id this device
//      already holds performs NO save and NO game replacement (OD-16);
//   4. the WIRING — the imperative half groups 1-3 cannot reach: the bind/retire lifecycle,
//      a gate that turns blocking mid-session, the teardown, the in-flight guard under real
//      concurrency, and a generation bump abandoning an in-flight import's write. Driven
//      through the service's injectable providers, so no configured `FirebaseApp` is needed.
//

import FirebaseFirestore
import FirebaseFunctions
import Foundation
import Testing
@testable import LicensePlateApp

// MARK: - Gate (fail-closed)

@MainActor
struct AccountTripDiscoveryGateTests {

    private let me = "user-me"

    private func decide(
        userId: String? = "user-me",
        authenticatedUserId: String? = "user-me",
        isCloudSyncHeld: Bool = false,
        isIdentityDetached: Bool = false,
        isChildPostureResolved: Bool = true
    ) -> AccountTripDiscoveryGateDecision {
        AccountTripDiscoveryGate.decide(
            userId: userId,
            authenticatedUserId: authenticatedUserId,
            isCloudSyncHeld: isCloudSyncHeld,
            isIdentityDetached: isIdentityDetached,
            isChildPostureResolved: isChildPostureResolved
        )
    }

    @Test func bindsWhenEveryPredicateIsSatisfied() {
        #expect(decide() == .bind(userId: me))
    }

    @Test func doesNotBindWithoutAUserId() {
        #expect(decide(userId: nil) == .skip(reason: .noUserId))
        #expect(decide(userId: "") == .skip(reason: .noUserId))
    }

    @Test func doesNotBindWhenTheAuthenticatedUidIsNotThePlayIdentity() {
        #expect(decide(authenticatedUserId: nil) == .skip(reason: .authMismatch))
        #expect(decide(authenticatedUserId: "someone-else") == .skip(reason: .authMismatch))
    }

    /// §3.1.1 item 7: `purgeSocialStateForDetachedIdentity` tears the cloud channels down on
    /// purpose — discovery must not re-hydrate what the detach is protecting.
    @Test func doesNotBindForADetachedIdentity() {
        #expect(decide(isIdentityDetached: true) == .skip(reason: .identityDetached))
    }

    /// FR-28: an unconsented child's gameplay cloud traffic is paused, reads included.
    @Test func doesNotBindWhileTheChildCloudSyncHoldIsOn() {
        #expect(decide(isCloudSyncHeld: true) == .skip(reason: .cloudSyncHeld))
    }

    /// The hole the FR-28 hold alone cannot close, and the reason this gate exists.
    ///
    /// `isGameplayCloudSyncPaused` resolves to false until this device has resolved the child
    /// posture for the uid. The live trip listeners were safe under that because they only ever
    /// enumerated LOCAL rows, and a fresh device has none. Discovery has no such floor: on a
    /// brand-new device it would bulk-import the account's whole trip history through
    /// `fetchTripBootstrapForMember` — the one trip callable with no server-side child gate —
    /// in the window before `users/{uid}` is read.
    @Test func doesNotBindWhileTheChildPostureIsUnresolved() {
        #expect(decide(isChildPostureResolved: false) == .skip(reason: .childPostureUnresolved))
    }

    @Test func aResolvedPostureNeedsEvidence_notMerelyTheAbsenceOfAHold() {
        // Nothing known about this uid on this device.
        #expect(!AccountTripDiscoveryGate.isChildPostureResolved(
            freshIsChildAccount: nil,
            cachedIsChildAccount: nil,
            isDeclaredChildIdentity: false
        ))
        // This session's fresh read landed — EITHER value decides the question.
        #expect(AccountTripDiscoveryGate.isChildPostureResolved(
            freshIsChildAccount: false,
            cachedIsChildAccount: nil,
            isDeclaredChildIdentity: false
        ))
        #expect(AccountTripDiscoveryGate.isChildPostureResolved(
            freshIsChildAccount: true,
            cachedIsChildAccount: nil,
            isDeclaredChildIdentity: false
        ))
        // A cached last resolution for this uid decides it too.
        #expect(AccountTripDiscoveryGate.isChildPostureResolved(
            freshIsChildAccount: nil,
            cachedIsChildAccount: false,
            isDeclaredChildIdentity: false
        ))
        // As does this device's declared under-13 lineage for the uid.
        #expect(AccountTripDiscoveryGate.isChildPostureResolved(
            freshIsChildAccount: nil,
            cachedIsChildAccount: nil,
            isDeclaredChildIdentity: true
        ))
    }

    /// Discovery may never be bound in a posture where the rest of the cloud trip channel is
    /// held: the gate's first four predicates must agree with the live listeners' funnel.
    @Test func gateAgreesWithTheLiveListenerFunnelOnTheFourSharedPredicates() {
        let cases: [(String?, String?, Bool, Bool)] = [
            ("user-me", "user-me", false, false),
            (nil, "user-me", false, false),
            ("", "user-me", false, false),
            ("user-me", nil, false, false),
            ("user-me", "other", false, false),
            ("user-me", "user-me", true, false),
            ("user-me", "user-me", false, true),
            ("user-me", "user-me", true, true),
        ]
        for (userId, authUid, held, detached) in cases {
            let funnel = LiveTripListenerEligibility.cloudChannelUserId(
                userId: userId,
                authenticatedUserId: authUid,
                isCloudSyncHeld: held,
                isIdentityDetached: detached
            )
            let gate = decide(
                userId: userId,
                authenticatedUserId: authUid,
                isCloudSyncHeld: held,
                isIdentityDetached: detached,
                isChildPostureResolved: true
            )
            #expect(gate.boundUserId == funnel)
        }
    }
}

// MARK: - Planner

@MainActor
struct AccountTripDiscoveryPlannerTests {

    private func plan(
        discovered: [UUID],
        local: Set<UUID> = [],
        inFlight: Set<UUID> = [],
        statuses: [UUID: DiscoveredTripStatus] = [:]
    ) -> AccountTripDiscoveryPlan {
        AccountTripDiscoveryPlanner.plan(
            discoveredSessionIds: discovered,
            localSessionIds: local,
            inFlightSessionIds: inFlight,
            statusById: statuses
        )
    }

    @Test func nothingDiscoveredIsNoWork() {
        #expect(plan(discovered: []).isEmpty)
    }

    @Test func aLiveTripIsImportedAndListenedTo() {
        let id = UUID()
        let result = plan(discovered: [id], statuses: [id: .live])
        #expect(result.importLive == [id])
        #expect(result.importEnded.isEmpty)
        #expect(result.importOrder == [id])
    }

    @Test func anEndedTripIsImportedWithoutListeners() {
        let id = UUID()
        let result = plan(discovered: [id], statuses: [id: .ended(endedAt: Date())])
        #expect(result.importEnded == [id])
        #expect(result.importLive.isEmpty, "an ended trip must never mint incremental listeners")
    }

    @Test func aCancelledTripIsNeverImported() {
        let id = UUID()
        let result = plan(discovered: [id], statuses: [id: .cancelled])
        #expect(result.skippedCancelled == [id])
        #expect(result.importOrder.isEmpty)
        #expect(result.retry.isEmpty)
    }

    /// OD-16: the client is authoritative for what it already holds. A trip this device has —
    /// whatever its status, whatever the server says — is never touched by discovery.
    @Test func aTripThisDeviceAlreadyHoldsIsSkippedBeforeItsStatusIsEvenConsulted() {
        let id = UUID()
        let result = plan(discovered: [id], local: [id], statuses: [id: .live])
        #expect(result.skippedLocal == [id])
        #expect(result.importOrder.isEmpty)
        #expect(AccountTripDiscoveryPlanner.idsNeedingStatus(
            discoveredSessionIds: [id],
            localSessionIds: [id],
            inFlightSessionIds: []
        ).isEmpty, "a locally-held id costs no session-doc read")
    }

    /// A Firestore listener normally delivers cache THEN server, so two passes over one id set
    /// are the norm. `session(byId:)` stays nil until the first import saves, so without this
    /// guard pass 2 would start a second interleaved import of the same trip.
    @Test func anImportAlreadyRunningIsNotStartedAgain() {
        let id = UUID()
        let result = plan(discovered: [id], inFlight: [id], statuses: [id: .live])
        #expect(result.skippedInFlight == [id])
        #expect(result.importOrder.isEmpty)
        #expect(AccountTripDiscoveryPlanner.idsNeedingStatus(
            discoveredSessionIds: [id],
            localSessionIds: [],
            inFlightSessionIds: [id]
        ).isEmpty)
    }

    /// The publish race: on a first publish the member doc is written BEFORE the parent
    /// session doc, so device B's discovery snapshot can fire while `trip_sessions/{id}` does
    /// not exist yet. That is NOT-YET-RESOLVED, never "import without listeners" — a genuinely
    /// active trip imported blind would sit on Home with no listeners and no self-heal.
    @Test func anUnresolvedSessionDocIsRetriedRatherThanDecided() {
        let id = UUID()
        let result = plan(discovered: [id], statuses: [id: .unresolved])
        #expect(result.retry == [id])
        #expect(result.importOrder.isEmpty)
        #expect(result.skippedCancelled.isEmpty)
    }

    /// Same rule for a status this build has never heard of: a future status must not be able
    /// to silently mint listeners or a silent listener-less import.
    @Test func aMissingStatusEntryIsRetried() {
        let id = UUID()
        let result = plan(discovered: [id], statuses: [:])
        #expect(result.retry == [id])
        #expect(result.importOrder.isEmpty)
    }

    @Test func liveTripsRestoreFirstAndEndedTripsNewestFirst() {
        let live = UUID()
        let oldest = UUID()
        let newest = UUID()
        let undated = UUID()
        let result = plan(
            discovered: [oldest, undated, live, newest],
            statuses: [
                live: .live,
                oldest: .ended(endedAt: Date(timeIntervalSince1970: 1_700_000_000)),
                newest: .ended(endedAt: Date(timeIntervalSince1970: 1_800_000_000)),
                undated: .ended(endedAt: nil),
            ]
        )
        #expect(result.importOrder == [live, newest, oldest, undated])
    }

    @Test func aMixedSnapshotIsSortedIntoEveryBranchAtOnce() {
        let live = UUID()
        let ended = UUID()
        let cancelled = UUID()
        let held = UUID()
        let importing = UUID()
        let racing = UUID()
        let result = plan(
            discovered: [live, ended, cancelled, held, importing, racing],
            local: [held],
            inFlight: [importing],
            statuses: [
                live: .live,
                ended: .ended(endedAt: Date()),
                cancelled: .cancelled,
                racing: .unresolved,
            ]
        )
        #expect(result.importLive == [live])
        #expect(result.importEnded == [ended])
        #expect(result.skippedCancelled == [cancelled])
        #expect(result.skippedLocal == [held])
        #expect(result.skippedInFlight == [importing])
        #expect(result.retry == [racing])
        #expect(AccountTripDiscoveryPlanner.idsNeedingStatus(
            discoveredSessionIds: [live, ended, cancelled, held, importing, racing],
            localSessionIds: [held],
            inFlightSessionIds: [importing]
        ) == [live, ended, cancelled, racing])
    }
}

// MARK: - Absent-only import (OD-16)

@MainActor
struct AccountTripDiscoveryImportTests {

    /// The absent-only path must return before it reaches the callable layer. Constructing the
    /// service with this keeps the test Firebase-free AND fails loudly if that ever stops
    /// being true (`functions` is resolved lazily, on first use only).
    private func unreachableFunctions() -> Functions {
        Issue.record("the absent-only import must not reach the callable layer")
        return Functions.functions()
    }

    @Test func aDiscoveredTripThisDeviceAlreadyHoldsIsNeverOverwritten() async throws {
        let sessionRepository = MockTripSessionRepository()
        let gameRepository = MockGameInstanceRepository()
        let eventRepository = MockTripActivityEventRepository()
        let sync = TripCanonicalRemoteSyncService(
            tripSessionRepository: sessionRepository,
            gameInstanceRepository: gameRepository,
            tripActivityEventRepository: eventRepository,
            functions: unreachableFunctions()
        )

        // A local-first trip with an unpublished status change and a game of its own.
        let sessionId = UUID()
        let local = TripSession(
            id: sessionId,
            name: "Local-first road trip",
            status: .active,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            createdBy: "user-me",
            startedAt: Date(timeIntervalSince1970: 1_700_000_100),
            participants: [TripParticipant(userId: "user-me", role: .owner)]
        )
        sessionRepository.seed(local)
        let game = GameInstance(
            definitionId: "license_plate",
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: "license_plate")
        )
        try gameRepository.upsert(instance: game)

        let imported = try await sync.importDiscoveredSessionIfAbsent(sessionId: sessionId)

        #expect(imported == nil, "discovery must not import over a session this device holds")
        let after = try #require(try sessionRepository.session(byId: sessionId))
        #expect(after.name == local.name)
        #expect(after.status == local.status)
        #expect(after.startedAt == local.startedAt)
        #expect(after.participants.map(\.userId) == local.participants.map(\.userId))
        let games = try gameRepository.fetchByTripSession(sessionId: sessionId)
        #expect(games.map(\.id) == [game.id], "the local games survive a discovery pass untouched")
        #expect(!sync.isIncrementallyListening(sessionId: sessionId),
                "skipping an id must not attach listeners either")
    }
}

// MARK: - Wiring (bind / retire / abandon)

/// A `ListenerRegistration` with no Firestore behind it, so the discovery channel can be
/// bound and retired in a unit test.
private final class FakeDiscoveryListenerRegistration: NSObject, ListenerRegistration {
    private(set) var removeCount = 0
    func remove() {
        removeCount += 1
    }
}

/// Counters the injected providers write to. A reference box, so the closures stored on the
/// service and the assertions below see the same values.
@MainActor
private final class DiscoveryWiringRecorder {
    var binds: [String] = []
    var bootstrapFetches: [UUID] = []
    var registrations: [FakeDiscoveryListenerRegistration] = []
}

@MainActor
struct AccountTripDiscoveryWiringTests {

    private let me = "user-me"

    /// The absent-only import must still never reach the callable layer; the wiring cases that
    /// DO import drive `fetchTripBootstrapBundleOverride` instead, which is above it.
    private func unreachableFunctions() -> Functions {
        Issue.record("the discovery wiring must not reach the callable layer")
        return Functions.functions()
    }

    private func makeService(
        sessionRepository: MockTripSessionRepository? = nil,
        gameRepository: MockGameInstanceRepository? = nil,
        eventRepository: MockTripActivityEventRepository? = nil,
        recorder: DiscoveryWiringRecorder
    ) -> TripCanonicalRemoteSyncService {
        let sync = TripCanonicalRemoteSyncService(
            tripSessionRepository: sessionRepository ?? MockTripSessionRepository(),
            gameInstanceRepository: gameRepository ?? MockGameInstanceRepository(),
            tripActivityEventRepository: eventRepository ?? MockTripActivityEventRepository(),
            functions: unreachableFunctions()
        )
        sync.currentUserIdProvider = { "user-me" }
        sync.isIdentityDetachedProvider = { _ in false }
        sync.cloudSyncHoldProvider = { false }
        sync.isChildPostureResolvedProvider = { _ in true }
        sync.discoveryListenerFactory = { userId, _ in
            recorder.binds.append(userId)
            let registration = FakeDiscoveryListenerRegistration()
            recorder.registrations.append(registration)
            return registration
        }
        return sync
    }

    /// An ENDED trip: `applyBootstrap` attaches no incremental listeners for one, which is what
    /// keeps these cases away from Firestore entirely.
    private func endedBundle(sessionId: UUID) -> TripBootstrapWireDTO {
        TripBootstrapWireDTO(
            session: TripSessionWireDTO(
                id: sessionId.uuidString,
                name: "Restored trip",
                status: TripSessionState.ended.rawValue,
                createdAt: 1_700_000_000,
                createdBy: "user-me",
                startedAt: 1_700_000_100,
                endedAt: 1_700_000_900,
                endedBy: "user-me",
                participants: [
                    TripParticipantWireItem(
                        userId: "user-me",
                        role: TripParticipantRole.owner.rawValue,
                        joinedAt: 1_700_000_000,
                        leftAt: nil,
                        teamId: nil
                    ),
                ]
            ),
            games: [],
            events: [],
            syncVersion: 1,
            nextEventCursor: nil
        )
    }

    private func settleMainActorWork() async {
        for _ in 0..<10 {
            await Task.yield()
        }
    }

    /// FINDING 1 (high). The FR-28 hold, a detach and an auth mismatch all turn on WITHOUT the
    /// uid changing, so `removeAllIncrementalListeners()` — the only other route to
    /// `stopAccountTripDiscovery()` — never fires. Without this, a guardian removing a
    /// consented child from the family leaves the child's discovery listener bound, and every
    /// later member snapshot keeps bulk-importing through `fetchTripBootstrapForMember`, the
    /// one trip callable with no server-side child gate.
    @Test func aGateThatTurnsBlockingMidSessionRetiresAnAlreadyBoundChannel() async {
        let recorder = DiscoveryWiringRecorder()
        let sync = makeService(recorder: recorder)
        var isHeld = false
        sync.cloudSyncHoldProvider = { isHeld }

        sync.startAccountTripDiscovery(userId: me)
        #expect(sync.discoveryBoundUserId == me)
        #expect(recorder.binds == [me])
        let boundGeneration = sync.discoveryGeneration

        // The guardian removes the child from the family: FR-28 hold on, uid unchanged.
        isHeld = true
        sync.startAccountTripDiscovery(userId: me)

        #expect(sync.discoveryBoundUserId == nil, "a blocked gate must RETIRE the bound channel")
        #expect(recorder.registrations.first?.removeCount == 1)
        #expect(sync.discoveryGeneration != boundGeneration,
                "the generation must move so an in-flight pass cannot act for the retired binding")
        #expect(recorder.binds == [me], "a blocked gate must not re-bind either")
        await settleMainActorWork()
    }

    /// An errored Firestore listener is terminal. Left bound, every later re-assert hook takes
    /// the same-uid short-circuit and discovery stays dead for the rest of the process — a trip
    /// started on another device would never arrive until a relaunch.
    @Test func aListenerErrorRetiresTheBindingSoTheNextHookRebinds() async {
        let recorder = DiscoveryWiringRecorder()
        let sync = makeService(recorder: recorder)
        var deliver: [@MainActor (Result<AccountTripDiscoverySnapshot, Error>) -> Void] = []
        sync.discoveryListenerFactory = { userId, onResult in
            recorder.binds.append(userId)
            deliver.append(onResult)
            let registration = FakeDiscoveryListenerRegistration()
            recorder.registrations.append(registration)
            return registration
        }

        sync.startAccountTripDiscovery(userId: me)
        let erroredGeneration = sync.discoveryGeneration
        deliver[0](.failure(NSError(domain: "FIRFirestoreErrorDomain", code: 9)))

        #expect(sync.discoveryBoundUserId == nil, "an errored listener must not stay bound")
        #expect(recorder.registrations[0].removeCount == 1)
        #expect(sync.discoveryGeneration != erroredGeneration)

        // The next hook for the SAME uid must bind a fresh listener, not short-circuit.
        sync.startAccountTripDiscovery(userId: me)
        #expect(recorder.binds == [me, me])
        #expect(sync.discoveryBoundUserId == me)

        // A late callback from the retired listener is stale and must not retire the new one.
        deliver[0](.failure(NSError(domain: "FIRFirestoreErrorDomain", code: 9)))
        #expect(sync.discoveryBoundUserId == me)
        #expect(recorder.registrations[1].removeCount == 0)
        await settleMainActorWork()
    }

    /// The same retirement, reached from the identity-change / purge route.
    @Test func removingAllIncrementalListenersRetiresDiscoveryAndBumpsItsGeneration() async {
        let recorder = DiscoveryWiringRecorder()
        let sync = makeService(recorder: recorder)

        sync.startAccountTripDiscovery(userId: me)
        #expect(sync.discoveryBoundUserId == me)
        let boundGeneration = sync.discoveryGeneration

        sync.removeAllIncrementalListeners()

        #expect(sync.discoveryBoundUserId == nil)
        #expect(recorder.registrations.first?.removeCount == 1)
        #expect(sync.discoveryGeneration != boundGeneration)
        await settleMainActorWork()
    }

    /// FINDING 2 (medium). On a cold or weak first launch all four re-assert hooks fire while
    /// the child posture is still unresolved; the resolution arrives later with no hook of its
    /// own. ContentView now re-asserts on that edge — this pins the half the service owns: the
    /// unresolved provider blocks the bind, and re-asserting once it resolves binds.
    @Test func anUnresolvedChildPostureBlocksTheBindAndTheResolvedEdgeBinds() async {
        let recorder = DiscoveryWiringRecorder()
        let sync = makeService(recorder: recorder)
        var isPostureResolved = false
        sync.isChildPostureResolvedProvider = { _ in isPostureResolved }

        sync.startAccountTripDiscovery(userId: me)
        #expect(sync.discoveryBoundUserId == nil)
        #expect(recorder.binds.isEmpty, "discovery must fail closed while the posture is unknown")

        // `users/{uid}.isChildAccount` lands; the coordinator publishes a resolved posture.
        isPostureResolved = true
        sync.startAccountTripDiscovery(userId: me)

        #expect(sync.discoveryBoundUserId == me)
        #expect(recorder.binds == [me])
        await settleMainActorWork()
    }

    /// FINDING 5 / the in-flight guard under real concurrency. A Firestore listener delivers
    /// cache THEN server, so two passes over one id overlap; `session(byId:)` stays nil until
    /// the first import saves, so only the in-flight set stops a double import.
    @Test func overlappingPassesOverOneIdImportItExactlyOnce() async throws {
        let recorder = DiscoveryWiringRecorder()
        let sessionRepository = MockTripSessionRepository()
        let sync = makeService(sessionRepository: sessionRepository, recorder: recorder)
        let sessionId = UUID()

        let bundle = endedBundle(sessionId: sessionId)
        var releaseFirstFetch: CheckedContinuation<Void, Never>?
        sync.fetchTripBootstrapBundleOverride = { id in
            recorder.bootstrapFetches.append(id)
            if recorder.bootstrapFetches.count == 1 {
                await withCheckedContinuation { continuation in releaseFirstFetch = continuation }
            }
            return bundle
        }

        let first = Task { @MainActor in
            try await sync.importDiscoveredSessionIfAbsent(sessionId: sessionId, emitsHydrationSignal: false)
        }
        await settleMainActorWork()

        // Pass 2 arrives while pass 1 is suspended in the callable.
        let second = try await sync.importDiscoveredSessionIfAbsent(sessionId: sessionId, emitsHydrationSignal: false)
        #expect(second == nil, "an import already running for the id must not be started again")

        releaseFirstFetch?.resume()
        let firstStatus = try await first.value
        #expect(firstStatus == .ended)
        #expect(recorder.bootstrapFetches == [sessionId], "exactly one bootstrap for one id")
        let stored = try #require(try sessionRepository.session(byId: sessionId))
        #expect(stored.id == sessionId)
    }

    /// FINDING 4 (medium). `purgeAllLocalUserData` tears the channel down and wipes SwiftData
    /// synchronously on the main actor, so an import suspended in the callable resumes AFTER
    /// the wipe. Its writes must be abandoned, or the signed-out device keeps gameplay rows
    /// for the identity that was just purged.
    @Test func aGenerationBumpWhileTheBundleIsInFlightAbandonsTheWrite() async throws {
        let recorder = DiscoveryWiringRecorder()
        let sessionRepository = MockTripSessionRepository()
        let gameRepository = MockGameInstanceRepository()
        let sync = makeService(
            sessionRepository: sessionRepository,
            gameRepository: gameRepository,
            recorder: recorder
        )
        let sessionId = UUID()

        sync.startAccountTripDiscovery(userId: me)
        let generation = sync.discoveryGeneration

        let bundle = endedBundle(sessionId: sessionId)
        sync.fetchTripBootstrapBundleOverride = { [weak sync] id in
            recorder.bootstrapFetches.append(id)
            // The teardown lands while the bundle is in flight.
            sync?.removeAllIncrementalListeners()
            return bundle
        }

        let status = try await sync.importDiscoveredSessionIfAbsent(
            sessionId: sessionId,
            emitsHydrationSignal: false,
            discoveryGenerationGuard: generation
        )

        #expect(status == nil, "a stale import must report nothing imported")
        #expect(recorder.bootstrapFetches == [sessionId])
        #expect(try sessionRepository.session(byId: sessionId) == nil,
                "a stale import must not write the session back after a purge")
        #expect(try gameRepository.fetchByTripSession(sessionId: sessionId).isEmpty,
                "nor its games")
        await settleMainActorWork()
    }

    /// The guard is scoped to discovery: the invite-driven restore passes none and always writes.
    @Test func anImportWithNoGenerationGuardIsNeverAbandoned() async throws {
        let recorder = DiscoveryWiringRecorder()
        let sessionRepository = MockTripSessionRepository()
        let sync = makeService(sessionRepository: sessionRepository, recorder: recorder)
        let sessionId = UUID()

        sync.startAccountTripDiscovery(userId: me)
        let bundle = endedBundle(sessionId: sessionId)
        sync.fetchTripBootstrapBundleOverride = { [weak sync] id in
            recorder.bootstrapFetches.append(id)
            sync?.removeAllIncrementalListeners()
            return bundle
        }

        let status = try await sync.importDiscoveredSessionIfAbsent(
            sessionId: sessionId,
            emitsHydrationSignal: false
        )

        #expect(status == .ended)
        #expect(try sessionRepository.session(byId: sessionId) != nil)
        await settleMainActorWork()
    }
}
