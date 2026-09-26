//
//  TripCanonicalRemoteSyncService.swift
//  LicensePlateApp
//
//  Step 12.5 — Publish local trip canonical state to Firestore (callable) and bootstrap/joiner incremental sync.
//

import Combine
import Foundation
import os
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

// MARK: - JSON helpers (HTTPS callable payloads)

enum TripCanonicalSyncJSON {
    static func jsonObject<T: Encodable>(encodable: T) throws -> Any {
        let data = try JSONEncoder().encode(encodable)
        return try JSONSerialization.jsonObject(with: data)
    }

    static func decodeBootstrap(any: Any) throws -> TripBootstrapWireDTO {
        let data = try JSONSerialization.data(withJSONObject: any)
        return try JSONDecoder().decode(TripBootstrapWireDTO.self, from: data)
    }
}

// MARK: - Firestore document → wire (incremental listeners)

private enum TripCanonicalFirestoreFields {
    static func gameWire(documentId: String, data: [String: Any]) -> GameInstanceWireDTO? {
        guard let definitionId = data["definitionId"] as? String,
              let sessionId = data["sessionId"] as? String else {
            return nil
        }
        let startedAt = timestampSeconds(data["startedAt"]) ?? 0
        let endedAt = timestampSeconds(data["endedAt"])
        return GameInstanceWireDTO(
            id: documentId,
            definitionId: definitionId,
            sessionId: sessionId,
            startedAt: startedAt,
            endedAt: endedAt,
            ruleSetDataBase64: data["ruleSetDataBase64"] as? String,
            commonConfigDataBase64: data["commonConfigDataBase64"] as? String,
            gameSpecificPayloadType: data["gameSpecificPayloadType"] as? String,
            gameSpecificPayloadVersion: data["gameSpecificPayloadVersion"] as? String,
            gameSpecificPayloadDataBase64: data["gameSpecificPayloadDataBase64"] as? String,
            teamsDataBase64: data["teamsDataBase64"] as? String
        )
    }

    static func eventWire(documentId: String, data: [String: Any]) -> TripActivityEventWireDTO? {
        guard let sessionId = data["sessionId"] as? String,
              let kind = data["kind"] as? String else {
            return nil
        }
        let ts = timestampSeconds(data["timestamp"]) ?? 0
        let payload = stringPayloadFromFirestore(data["payload"])
        return TripActivityEventWireDTO(
            id: documentId,
            sessionId: sessionId,
            kind: kind,
            timestamp: ts,
            actorId: data["actorId"] as? String,
            payload: payload
        )
    }

    /// Firestore returns `payload` as `[String: Any]` (e.g. `Int64` values); cast to `[String: String]` always failed, so
    /// `region_found` merged with `payload == nil` and discovery replay skipped every peer find.
    private static func stringPayloadFromFirestore(_ value: Any?) -> [String: String]? {
        if value == nil { return nil }
        if let p = value as? [String: String] { return p }
        guard let dict = value as? [String: Any] else { return nil }
        var out: [String: String] = [:]
        for (k, v) in dict {
            if v is NSNull { continue }
            if let s = v as? String {
                out[k] = s
            } else if let n = v as? NSNumber {
                out[k] = n.stringValue
            } else if let n = v as? Int {
                out[k] = String(n)
            } else if let n = v as? Int64 {
                out[k] = String(n)
            } else if let n = v as? Double {
                out[k] = String(n)
            } else if let b = v as? Bool {
                out[k] = b ? "true" : "false"
            } else {
                out[k] = String(describing: v)
            }
        }
        return out.isEmpty ? nil : out
    }

    private static func timestampSeconds(_ value: Any?) -> Double? {
        if let ts = value as? Timestamp {
            return ts.dateValue().timeIntervalSince1970
        }
        return nil
    }
}

// MARK: - Which locally-held sessions this device must listen to

/// Trip-end propagation (owner regression 2026-09-07): which sessions this device must hold
/// canonical listeners for, independent of which trip screen — if any — has been opened this
/// process.
///
/// Live trip state, the trip END above all, reaches a device only through
/// `trip_sessions/{id}/activity_events`. Listeners used to be registered per OPENED trip
/// (bootstrap, publish, the trip/game screens, the recap host), so a device sitting on Home
/// that had not opened the trip since launch heard nothing until it did. The registry is
/// keyed per session and `startIncrementalListeningIfNeeded` is a no-op when a registration
/// exists, so re-asserting this whole set on launch and on every foreground is free.
nonisolated enum LiveTripListenerEligibility {

    /// Sessions worth a listener: still live locally (`created`/`active`) with the current user
    /// on the roster and not departed.
    ///
    /// - `authenticatedUserId` must equal `userId` — a session whose play identity is a purely
    ///   local guest id (or a retired uid, §3.1.1 item 7) has no cloud document to listen to,
    ///   and a listener started under an identity that is not the one Firestore will
    ///   authenticate as would also mis-attribute an FR-69 permission-denied eviction.
    /// - `isCloudSyncHeld` (FR-28, unconsented child) suppresses everything: gameplay cloud
    ///   traffic is paused for that posture, and the publish path re-arms listeners on consent.
    /// - `isIdentityDetached` (§3.1.1 item 7) likewise: `purgeSocialStateForDetachedIdentity`
    ///   tears these listeners down on purpose, and a re-assert must not undo that.
    static func sessionIdsNeedingListeners(
        sessions: [TripSession],
        userId: String?,
        authenticatedUserId: String?,
        isCloudSyncHeld: Bool,
        isIdentityDetached: Bool = false
    ) -> [UUID] {
        guard let userId = cloudChannelUserId(
            userId: userId,
            authenticatedUserId: authenticatedUserId,
            isCloudSyncHeld: isCloudSyncHeld,
            isIdentityDetached: isIdentityDetached
        ) else {
            return []
        }
        return sessions
            .filter { $0.status == .active || $0.status == .created }
            .filter { session in
                session.createdBy == userId
                    || session.participants.contains { $0.userId == userId && $0.leftAt == nil }
            }
            .map(\.id)
    }

    /// The four identity/COPPA predicates above, on their own: the single funnel for the whole
    /// cloud trip channel. Returns the uid the channel may be keyed to, or nil.
    ///
    /// Extracted (§3.1.1 item 19) because account-scoped trip DISCOVERY has to apply exactly
    /// these predicates and cannot reuse `sessionIdsNeedingListeners`, which fuses them with a
    /// local-row filter — and a device with no local rows is the entire point of discovery.
    /// Discovery adds a fifth, discovery-only predicate on top (see `AccountTripDiscoveryGate`).
    static func cloudChannelUserId(
        userId: String?,
        authenticatedUserId: String?,
        isCloudSyncHeld: Bool,
        isIdentityDetached: Bool
    ) -> String? {
        guard !isCloudSyncHeld, !isIdentityDetached,
              let userId, !userId.isEmpty,
              let authenticatedUserId, authenticatedUserId == userId else {
            return nil
        }
        return userId
    }
}

@MainActor
protocol TripCanonicalRemoteSyncing: AnyObject {
    func publishFullSession(sessionId: UUID) async throws
    func appendEventToRemote(_ event: TripActivityEvent) async throws -> GameplayEventAppendOutcome
    func bootstrapMemberSession(sessionId: UUID) async throws
    func startIncrementalListeningIfNeeded(sessionId: UUID)
    func markTripCancelledRemote(sessionId: UUID) async throws
    /// Owner-only: remove a participant (kick). Server writes `participant_left` with `leaveReason=kicked`.
    func removeParticipantAsOwner(sessionId: UUID, removedUserId: String) async throws
}

@MainActor
final class TripCanonicalRemoteSyncService: ObservableObject, TripCanonicalRemoteSyncing {

    static let shared = TripCanonicalRemoteSyncService(
        tripSessionRepository: TripSessionRepository.shared,
        gameInstanceRepository: GameInstanceRepository.shared,
        tripActivityEventRepository: TripActivityEventRepository.shared
    )

    private let tripSessionRepository: TripSessionRepositoryProtocol
    private let gameInstanceRepository: GameInstanceRepositoryProtocol
    private let tripActivityEventRepository: TripActivityEventRepositoryProtocol
    /// Resolved on FIRST USE, not at construction: `Functions.functions()` needs a configured
    /// `FirebaseApp`, and the absent-only discovery import (§3.1.1 item 19) returns before it
    /// ever reaches the callable layer — which is what lets that OD-16 invariant be pinned by a
    /// Firebase-free unit test over the existing repository fakes.
    private let functionsFactory: () -> Functions
    private lazy var functions: Functions = functionsFactory()

    private var incrementalGameListeners: [String: ListenerRegistration] = [:]
    private var incrementalEventListeners: [String: ListenerRegistration] = [:]

    // MARK: - Account-scoped trip discovery (§3.1.1 item 19)

    /// ONE live `collectionGroup("members").whereField("memberUserId", isEqualTo: uid)` listener:
    /// the account's whole trip membership, so a trip started on device A reaches device B, and
    /// a device that has never seen the account restores everything it created or joined.
    ///
    /// Owned HERE, beside the per-session listeners, and retired with them — never in
    /// `TripInviteRepository`, whose `stopListening` runs on every identity change and on the
    /// detached-identity purge (2026-09-07 regression note in that file).
    private var discoveryListener: ListenerRegistration?
    private(set) var discoveryBoundUserId: String?
    /// Monotonic, bumped on every bind and every teardown, so a callback that outlives its
    /// binding (the handler hops through `Task { @MainActor }`) cannot act for a retired uid.
    private(set) var discoveryGeneration = 0
    /// Ids whose import is running right now — the guard that stops the cache-then-server
    /// snapshot pair from double-importing (`session(byId:)` is still nil mid-import).
    private var discoveryImportsInFlight: Set<UUID> = []
    /// Ids whose status could not be resolved, or whose import failed, this pass.
    private var discoveryRetryIds: Set<UUID> = []
    private var discoveryRetryTask: Task<Void, Never>?
    private var discoveryRetryAttempt = 0
    /// Serializes passes, so a cache snapshot and the server snapshot behind it do not
    /// interleave their imports.
    private var discoveryPassTask: Task<Void, Never>?

    /// Bounded retry budget for the publish race (the member doc is written BEFORE the session
    /// doc, so a snapshot can arrive while `trip_sessions/{id}` does not exist yet) and for a
    /// failed import. 5 attempts / 31 s, then the next re-assert hook re-drives it.
    private static let discoveryRetryDelays: [TimeInterval] = [1, 2, 4, 8, 16]

    /// F-6 (FR-28): while true (unconsented child), canonical publish is a silent no-op —
    /// all callers are best-effort, and the SyncCoordinator retry machinery republishes
    /// once consent lifts the hold. Injectable for tests.
    var cloudSyncHoldProvider: () -> Bool = { ChildRestrictedModeService.shared.isGameplayCloudSyncPaused }

    /// FR-69 (F-25): the uid a session's listeners are started for, captured at
    /// registration so a later permission-denied can be attributed to THAT identity
    /// (`TripEvictionDetectionPolicy`). Injectable for tests.
    var currentUserIdProvider: () -> String? = { Auth.auth().currentUser?.uid }

    /// §3.1.1 item 7 (2026-08-28): a retired (detached) uid never keys a cloud channel — and
    /// `purgeSocialStateForDetachedIdentity` explicitly tears these listeners down, so the
    /// launch/foreground re-assert must not put them straight back. Injectable for tests.
    var isIdentityDetachedProvider: (String?) -> Bool = { AgeGateStore.shared.isIdentityDetached($0) }

    /// §3.1.1 item 19, discovery only: has this device DECIDED whether `uid` is a child
    /// account? `isCloudSyncHeld` (FR-28) resolves to false on a device that has never
    /// resolved the posture for this uid, which is exactly the fresh-device case discovery
    /// fires on — so discovery needs a positive resolution signal, not the absence of a hold.
    /// Injectable for tests.
    var isChildPostureResolvedProvider: (String) -> Bool = { userId in
        AccountTripDiscoveryGate.isChildPostureResolved(
            freshIsChildAccount: UserRepository.shared.isChildAccount(for: userId),
            cachedIsChildAccount: ChildSignalCache.shared.cachedIsChildAccount(for: userId),
            isDeclaredChildIdentity: AgeGateStore.shared.isDeclaredChildUserId(userId)
                || AgeGateStore.shared.isPendingDeclaration(userId: userId)
        )
    }

    /// §3.1.1 item 19, discovery only: attaches the account-scoped membership query and calls
    /// back on the main actor with the discovered session ids. The Firestore types stay behind
    /// this seam so the whole bind / rebind / retire lifecycle — the imperative half the pure
    /// gate and planner cannot cover — is pinnable without a configured `FirebaseApp`.
    var discoveryListenerFactory: (
        _ userId: String,
        _ onResult: @escaping @MainActor (Result<AccountTripDiscoverySnapshot, Error>) -> Void
    ) -> ListenerRegistration = { userId, onResult in
        Firestore.firestore()
            .collectionGroup("members")
            .whereField("memberUserId", isEqualTo: userId)
            .addSnapshotListener { snapshot, error in
                Task { @MainActor in
                    if let error {
                        onResult(.failure(error))
                        return
                    }
                    guard let snapshot else { return }
                    let sessionIds = snapshot.documents.compactMap { doc -> UUID? in
                        guard let parentId = doc.reference.parent.parent?.documentID else { return nil }
                        return UUID(uuidString: parentId)
                    }
                    onResult(.success(AccountTripDiscoverySnapshot(
                        sessionIds: sessionIds,
                        isFromCache: snapshot.metadata.isFromCache
                    )))
                }
            }
    }

    /// Test seam for the REMOTE half of a bootstrap (App Check readiness, the
    /// `fetchTripBootstrapForMember` callable, decode). Nil in production. Injected, the import
    /// path — including the generation guard that abandons a stale write — runs with no
    /// configured `FirebaseApp` and no network.
    var fetchTripBootstrapBundleOverride: ((UUID) async throws -> TripBootstrapWireDTO)?

    /// FR-69 (F-25): what to do when a live session's listeners are denied for the
    /// identity they were started for — the only signal an evicted device ever gets.
    /// Injectable for tests; the default applies the local eviction.
    var evictionHandler: (UUID, String, String?) -> Void = { sessionId, listenerUserId, currentUserId in
        do {
            try TripParticipationService.shared.applyServerEviction(
                sessionId: sessionId,
                listenerUserId: listenerUserId,
                currentUserId: currentUserId
            )
        } catch {
            print("TripCanonicalRemoteSyncService: apply server eviction failed \(error)")
        }
    }

    /// Serializes concurrent `publishFullSession` for the same trip (`startTrip` vs combined setup publish).
    private var publishTailBySessionId: [UUID: (UUID, Task<Void, Error>)] = [:]

    private let hydrationSubject = PassthroughSubject<UUID, Never>()
    /// Emits session id after successful bootstrap or incremental merge worth a UI refresh.
    var hydrationSignal: AnyPublisher<UUID, Never> {
        hydrationSubject.eraseToAnyPublisher()
    }

    private let fairnessResolutionSubject = PassthroughSubject<FairnessResolutionInfo, Never>()
    /// Step 13 — after sync reconciles a superseded local find (VM subscribes for toast).
    var fairnessResolutionSignal: AnyPublisher<FairnessResolutionInfo, Never> {
        fairnessResolutionSubject.eraseToAnyPublisher()
    }

    private let tripEndedRemotelySubject = PassthroughSubject<TripEndedRemotelyInfo, Never>()
    var tripEndedRemotelySignal: AnyPublisher<TripEndedRemotelyInfo, Never> {
        tripEndedRemotelySubject.eraseToAnyPublisher()
    }

    /// Called by `SyncCoordinator` after applying server fairness reconciliation locally.
    func publishFairnessResolution(_ info: FairnessResolutionInfo) {
        fairnessResolutionSubject.send(info)
    }

    init(
        tripSessionRepository: TripSessionRepositoryProtocol,
        gameInstanceRepository: GameInstanceRepositoryProtocol,
        tripActivityEventRepository: TripActivityEventRepositoryProtocol,
        functions: @autoclosure @escaping () -> Functions = Functions.functions()
    ) {
        self.tripSessionRepository = tripSessionRepository
        self.gameInstanceRepository = gameInstanceRepository
        self.tripActivityEventRepository = tripActivityEventRepository
        self.functionsFactory = functions
    }

    func publishFullSession(sessionId: UUID) async throws {
        let sid = sessionId
        let chainId = UUID()
        let predecessor = publishTailBySessionId[sid]?.1
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            if let predecessor {
                _ = try? await predecessor.value
            }
            try await self.publishFullSessionBody(sessionId: sid)
        }
        publishTailBySessionId[sid] = (chainId, task)
        defer {
            if publishTailBySessionId[sid]?.0 == chainId {
                publishTailBySessionId[sid] = nil
            }
        }
        try await task.value
    }

    private func publishFullSessionBody(sessionId: UUID) async throws {
        // FR-28: cloud gameplay collection pauses for an unconsented child; local play
        // continues and the canonical state publishes after consent.
        guard !cloudSyncHoldProvider() else { return }
        try await AppCheckReadiness.ensureCallablePrerequisites()
        guard let session = try tripSessionRepository.session(byId: sessionId) else {
            throw TripCanonicalRemoteSyncError.sessionNotFoundLocally
        }
        let games = try gameInstanceRepository.fetchByTripSession(sessionId: sessionId)
        let wireSession = TripCanonicalMapper.wireSession(from: session)
        let wireGames = games.map { TripCanonicalMapper.wireGame(from: $0) }

        let sessionObj = try TripCanonicalSyncJSON.jsonObject(encodable: wireSession)
        var gamesArr: [Any] = []
        for g in wireGames {
            gamesArr.append(try TripCanonicalSyncJSON.jsonObject(encodable: g))
        }

        let fn = functions.httpsCallable("publishTripCanonicalState")
        _ = try await fn.call([
            "tripSessionId": sessionId.uuidString,
            "session": sessionObj,
            "games": gamesArr,
        ].addingClientMetadata())
        // Creators never call `bootstrapMemberSession`; without listeners they miss peers’ `activity_events`.
        startIncrementalListeningIfNeeded(sessionId: sessionId)
    }

    func appendEventToRemote(_ event: TripActivityEvent) async throws -> GameplayEventAppendOutcome {
        try await AppCheckReadiness.ensureCallablePrerequisites()
        let wire = TripCanonicalMapper.wireEvent(from: event)
        let eventObj = try TripCanonicalSyncJSON.jsonObject(encodable: wire)
        let fn = functions.httpsCallable("appendTripActivityEvent")
        let result = try await fn.call([
            "tripSessionId": event.sessionId.uuidString,
            "event": eventObj,
        ].addingClientMetadata())
        return try GameplayAppendCallableResponseParser.outcome(from: result.data, uploadedEventId: event.id)
    }

    /// Invite-driven restore. DESTRUCTIVE by design and by its two existing callers
    /// (`TripInviteRepository`, `PendingTripsViewModel`): it rewrites the local row and
    /// replaces the games from the server bundle. Account-scoped discovery must NOT use it —
    /// see `importDiscoveredSessionIfAbsent`.
    func bootstrapMemberSession(sessionId: UUID) async throws {
        _ = try await applyBootstrap(sessionId: sessionId, emitsHydrationSignal: true)
    }

    /// §3.1.1 item 19 — ABSENT-ONLY import (OD-16). A session this device already holds is
    /// left completely untouched: an unpublished local-first game, an offline status change,
    /// anything the client is authoritative for survives a restore pass byte-identical.
    ///
    /// The in-flight set is the second half of that guarantee: `session(byId:)` stays nil
    /// until the bootstrap saves, so the cache-then-server pair of snapshots a Firestore
    /// listener normally delivers would otherwise start two interleaved imports of one id.
    ///
    /// - Parameter discoveryGenerationGuard: the discovery binding this import belongs to. When
    ///   the generation has moved by the time the remote bundle lands — a teardown, a re-bind,
    ///   a hard sign-out that wiped local data — the import is ABANDONED before it writes
    ///   anything. Nil for callers that are not part of a discovery pass.
    /// - Returns: the status the imported session landed with, or nil when nothing was imported.
    @discardableResult
    func importDiscoveredSessionIfAbsent(
        sessionId: UUID,
        emitsHydrationSignal: Bool = true,
        discoveryGenerationGuard: Int? = nil
    ) async throws -> TripSessionState? {
        guard (try? tripSessionRepository.session(byId: sessionId)) == nil else { return nil }
        guard !discoveryImportsInFlight.contains(sessionId) else { return nil }
        discoveryImportsInFlight.insert(sessionId)
        defer { discoveryImportsInFlight.remove(sessionId) }
        return try await applyBootstrap(
            sessionId: sessionId,
            emitsHydrationSignal: emitsHydrationSignal,
            discoveryGenerationGuard: discoveryGenerationGuard
        )
    }

    /// The remote half of a bootstrap, behind one seam so the import path is testable without
    /// Firebase (`fetchTripBootstrapBundleOverride`).
    private func fetchTripBootstrapBundle(sessionId: UUID) async throws -> TripBootstrapWireDTO {
        if let fetchTripBootstrapBundleOverride {
            return try await fetchTripBootstrapBundleOverride(sessionId)
        }
        try await AppCheckReadiness.ensureCallablePrerequisites()
        let fn = functions.httpsCallable("fetchTripBootstrapForMember")
        let result = try await fn.call((["tripSessionId": sessionId.uuidString] as [String: Any]).addingClientMetadata())
        guard let data = result.data as? [String: Any] else {
            throw TripCanonicalRemoteSyncError.invalidCallableResponse
        }
        return try TripCanonicalSyncJSON.decodeBootstrap(any: data)
    }

    /// - Parameter emitsHydrationSignal: false while a bulk restore is running, so a 25-trip
    ///   pass fires ONE Home reload + re-assert instead of 25 (each signal drives
    ///   `ActiveTripsListViewModel.load`, which replays every event of every active trip).
    /// - Returns: nil only when a discovery-scoped import was abandoned as stale — every other
    ///   caller passes no guard and always gets a status.
    @discardableResult
    private func applyBootstrap(
        sessionId: UUID,
        emitsHydrationSignal: Bool,
        discoveryGenerationGuard: Int? = nil
    ) async throws -> TripSessionState? {
        let bundle = try await fetchTripBootstrapBundle(sessionId: sessionId)
        // The ONE place a stale discovery write is stopped: everything above is a read, and
        // everything below is a local write. The generation moves on a teardown or a re-bind,
        // and a hard sign-out wipes SwiftData between the two — nothing may write back.
        if let discoveryGenerationGuard, discoveryGenerationGuard != discoveryGeneration {
            TripDiscoveryDiagnostics.log(
                "import abandoned \(TripDiscoveryDiagnostics.shortSessionId(sessionId)) "
                + "gen=\(discoveryGenerationGuard) (bound=\(discoveryGeneration))"
            )
            return nil
        }

        let domainSession = TripCanonicalMapper.domainSession(from: bundle.session)
        try tripSessionRepository.save(session: domainSession)

        let domainGames: [GameInstance] = try bundle.games.map { try TripCanonicalMapper.domainGame(from: $0) }
        try gameInstanceRepository.replaceGamesForSession(sessionId: sessionId, instances: domainGames)

        let domainEvents: [TripActivityEvent] = bundle.events.compactMap { TripCanonicalMapper.domainEvent(from: $0) }
        try tripActivityEventRepository.importEventsIfAbsent(domainEvents)
        try reconcileGameLifecycleFromStoredEvents(sessionId: sessionId)

        if emitsHydrationSignal {
            hydrationSubject.send(sessionId)
        }
        // §3.1.1 item 19: listeners only for a trip that is still live. This also closes the
        // pre-existing leak where the invite-driven restore attached two permanent Firestore
        // listeners to every ENDED trip it hydrated, released only by a full teardown.
        let isLive = domainSession.status == .created || domainSession.status == .active
        if isLive {
            startIncrementalListeningIfNeeded(sessionId: sessionId)
        }
        return domainSession.status
    }

    /// Re-asserts canonical listeners for every session this device still holds as live.
    ///
    /// Called at launch, on every foreground, and whenever the signed-in identity settles —
    /// this is what makes a remote trip end (and an FR-69 roster eviction) reach a device that
    /// has not opened the trip since the process started. Idempotent per session, so repeated
    /// calls cost one repository read and nothing else. Returns the ids it listened to.
    @discardableResult
    func startIncrementalListeningForLocalSessions(userId: String?) -> [UUID] {
        let sessions = (try? tripSessionRepository.loadActiveSessions(userId: userId)) ?? []
        let authenticatedUserId = currentUserIdProvider()
        let isCloudSyncHeld = cloudSyncHoldProvider()
        let isIdentityDetached = isIdentityDetachedProvider(userId)
        let sessionIds = LiveTripListenerEligibility.sessionIdsNeedingListeners(
            sessions: sessions,
            userId: userId,
            authenticatedUserId: authenticatedUserId,
            isCloudSyncHeld: isCloudSyncHeld,
            isIdentityDetached: isIdentityDetached
        )
        TripEndSyncDiagnostics.log(
            "re-assert: userId=\(userId ?? "nil") authUid=\(authenticatedUserId ?? "nil") hold=\(isCloudSyncHeld) detached=\(isIdentityDetached) "
            + "localLive=\(sessions.map { "\($0.id.uuidString.prefix(8)):\($0.status.rawValue):by=\(String(describing: $0.createdBy).prefix(12)):p=\($0.participants.count)" }) "
            + "eligible=\(sessionIds.map { $0.uuidString.prefix(8) })"
        )
        for sessionId in sessionIds {
            startIncrementalListeningIfNeeded(sessionId: sessionId)
        }
        return sessionIds
    }

    // MARK: - Account-scoped trip discovery (§3.1.1 item 19)

    /// Re-asserts BOTH halves of this device's cloud trip channel: the per-session listeners
    /// for the trips it already holds, and the account-scoped discovery listener that finds the
    /// ones it does not.
    ///
    /// Wired to the four hooks that already re-assert the channel (launch, foreground, identity
    /// settle, hydration). Deliberately a separate function rather than folding discovery into
    /// `startIncrementalListeningForLocalSessions`, whose name would then lie about enumerating
    /// local rows only. Fire-and-forget: nothing here blocks the UI.
    func reassertTripCloudChannels(userId: String?) {
        startIncrementalListeningForLocalSessions(userId: userId)
        startAccountTripDiscovery(userId: userId)
    }

    /// Binds the discovery listener, or silently does nothing — never a state change on a
    /// blocked gate, so a held posture cannot be told apart from an idle one by the UI.
    func startAccountTripDiscovery(userId: String?) {
        let decision = AccountTripDiscoveryGate.decide(
            userId: userId,
            authenticatedUserId: currentUserIdProvider(),
            isCloudSyncHeld: cloudSyncHoldProvider(),
            isIdentityDetached: isIdentityDetachedProvider(userId),
            isChildPostureResolved: (userId.map { isChildPostureResolvedProvider($0) } ?? false)
        )
        guard let uid = decision.boundUserId else {
            if case .skip(let reason) = decision {
                TripDiscoveryDiagnostics.log(
                    "gate.skip reason=\(reason.rawValue) uid=\(TripDiscoveryDiagnostics.shortUid(userId))"
                )
            }
            // A gate that turns BLOCKING mid-session retires the channel. The FR-28 hold
            // arriving (a guardian removes a consented child from the family), a detach, or an
            // auth mismatch all leave the uid UNCHANGED, so `removeAllIncrementalListeners()`
            // never fires — without this, an already-bound listener keeps delivering member
            // snapshots and keeps bulk-importing through `fetchTripBootstrapForMember`, the one
            // trip callable with no server-side child gate. Idempotent: a no-op when nothing
            // was bound, which is the ordinary signed-out case.
            stopAccountTripDiscovery()
            return
        }

        if discoveryBoundUserId == uid, discoveryListener != nil {
            redriveDiscoveryRetriesIfIdle()
            return
        }
        stopAccountTripDiscovery()
        discoveryGeneration &+= 1
        discoveryBoundUserId = uid
        let generation = discoveryGeneration
        TripDiscoveryDiagnostics.log("bind gen=\(generation) uid=\(TripDiscoveryDiagnostics.shortUid(uid))")

        discoveryListener = discoveryListenerFactory(uid) { [weak self] result in
            guard let self else { return }
            guard self.discoveryGeneration == generation else {
                TripDiscoveryDiagnostics.log(
                    "snap.stale gen=\(generation) (bound=\(self.discoveryGeneration)) dropped"
                )
                return
            }
            switch result {
            case .failure(let error):
                let ns = error as NSError
                // Includes FAILED_PRECONDITION while the collection-group index builds.
                // Silent, never a user-visible failure. An errored Firestore listener is
                // TERMINAL, so the binding is retired here: left bound, every later hook would
                // take the same-uid short-circuit above and discovery would stay dead for the
                // rest of the process. Retired, the next re-assert hook (launch, foreground,
                // identity settle, profile merged, posture change) binds a fresh listener.
                TripDiscoveryDiagnostics.log(
                    "snap.error gen=\(generation) domain=\(ns.domain) code=\(ns.code) — retired, rebinds on next hook"
                )
                self.stopAccountTripDiscovery()
            case .success(let snapshot):
                TripDiscoveryDiagnostics.log(
                    "snap gen=\(generation) ids=\(snapshot.sessionIds.count) fromCache=\(snapshot.isFromCache)"
                )
                self.runDiscoveryPass(sessionIds: snapshot.sessionIds, generation: generation)
            }
        }
    }

    func stopAccountTripDiscovery() {
        let wasBound = discoveryListener != nil || discoveryBoundUserId != nil
        discoveryListener?.remove()
        discoveryListener = nil
        discoveryRetryTask?.cancel()
        discoveryRetryTask = nil
        // A pass suspended inside `fetchTripBootstrapForMember` must not resume and write rows
        // for an identity that has just been torn down: `purgeAllLocalUserData` runs
        // `removeAllIncrementalListeners()` → here and then wipes SwiftData, all synchronously
        // on the main actor, so the import resumes AFTER the wipe. Cancellation is best-effort
        // (the callable await is not necessarily cancellation-aware) — the generation bump
        // below is what actually abandons the write, checked after every await in the pass and
        // again inside `applyBootstrap` before its first repository call.
        discoveryPassTask?.cancel()
        discoveryPassTask = nil
        discoveryRetryIds.removeAll()
        discoveryRetryAttempt = 0
        if wasBound {
            TripDiscoveryDiagnostics.log(
                "unbind gen=\(discoveryGeneration) uid=\(TripDiscoveryDiagnostics.shortUid(discoveryBoundUserId))"
            )
            discoveryGeneration &+= 1
        }
        discoveryBoundUserId = nil
    }

    /// Passes run strictly one after another (cache snapshot, then the server snapshot behind
    /// it), so imports never interleave.
    private func runDiscoveryPass(sessionIds: [UUID], generation: Int) {
        let predecessor = discoveryPassTask
        discoveryPassTask = Task { @MainActor [weak self] in
            _ = await predecessor?.value
            guard let self, self.discoveryGeneration == generation else { return }
            await self.performDiscoveryPass(sessionIds: sessionIds, generation: generation)
        }
    }

    private func performDiscoveryPass(sessionIds: [UUID], generation: Int) async {
        // Probed by primary key, one fetch per discovered id — and across EVERY status, so a
        // locally-held ended or cancelled trip is skipped too.
        let localIds = Set(sessionIds.filter { (try? tripSessionRepository.session(byId: $0)) != nil })
        let needStatus = AccountTripDiscoveryPlanner.idsNeedingStatus(
            discoveredSessionIds: sessionIds,
            localSessionIds: localIds,
            inFlightSessionIds: discoveryImportsInFlight
        )
        var statusById: [UUID: DiscoveredTripStatus] = [:]
        for sessionId in needStatus {
            guard discoveryGeneration == generation else { return }
            statusById[sessionId] = await resolveDiscoveredStatus(sessionId: sessionId)
        }
        guard discoveryGeneration == generation else { return }

        let plan = AccountTripDiscoveryPlanner.plan(
            discoveredSessionIds: sessionIds,
            localSessionIds: localIds,
            inFlightSessionIds: discoveryImportsInFlight,
            statusById: statusById
        )
        TripDiscoveryDiagnostics.log(
            "plan import=\(plan.importOrder.count) attach=\(plan.importLive.count) "
            + "skipLocal=\(plan.skippedLocal.count) skipCancelled=\(plan.skippedCancelled.count) "
            + "retry=\(plan.retry.count) inFlight=\(plan.skippedInFlight.count)"
        )

        var imported = 0
        var lastImportedId: UUID?
        var failed: Set<UUID> = []
        for sessionId in plan.importOrder {
            guard discoveryGeneration == generation else { return }
            do {
                // Hydration is coalesced: ONE signal for the whole pass, below.
                if let status = try await importDiscoveredSessionIfAbsent(
                    sessionId: sessionId,
                    emitsHydrationSignal: false,
                    discoveryGenerationGuard: generation
                ) {
                    imported += 1
                    lastImportedId = sessionId
                    // Derived from the status the bootstrap actually landed with, NOT from the
                    // plan: a trip can end server-side between this device's status read and
                    // the bootstrap, and `applyBootstrap` attaches from the payload. The owner
                    // is told to verify the fix by reading this token, so it may not disagree
                    // with what was actually attached.
                    let attachedListeners = status == .created || status == .active
                    TripDiscoveryDiagnostics.log(
                        "import ok \(TripDiscoveryDiagnostics.shortSessionId(sessionId)) "
                        + "status=\(status.rawValue) listeners=\(attachedListeners ? "yes" : "no")"
                    )
                }
            } catch {
                failed.insert(sessionId)
                let ns = error as NSError
                TripDiscoveryDiagnostics.log(
                    "import failed \(TripDiscoveryDiagnostics.shortSessionId(sessionId)) "
                    + "domain=\(ns.domain) code=\(ns.code)"
                )
            }
        }

        guard discoveryGeneration == generation else { return }
        discoveryRetryIds = Set(plan.retry).union(failed)
        // ORDER IS LOAD-BEARING: the hydration signal below re-enters `startAccountTripDiscovery`
        // SYNCHRONOUSLY (Combine send → ContentView `.onReceive` → `reassertTripCloudChannels`).
        // With the retry still unscheduled, `redriveDiscoveryRetriesIfIdle` would see a nil
        // retry task, reset the attempt counter and launch an immediate extra pass — turning
        // the bounded [1,2,4,8,16] s budget into a ~1 s poll that never reports "budget spent".
        scheduleDiscoveryRetry(generation: generation)
        if imported > 0, let lastImportedId {
            // One reload + one re-assert for the whole restore, not one per trip.
            hydrationSubject.send(lastImportedId)
        }
    }

    /// The publish race and a transient failure are the same shape: not decided yet. Never
    /// "import without listeners" — a genuinely active trip imported blind would sit on Home
    /// with no listeners and no self-heal.
    private func scheduleDiscoveryRetry(generation: Int) {
        discoveryRetryTask?.cancel()
        discoveryRetryTask = nil
        guard !discoveryRetryIds.isEmpty else {
            discoveryRetryAttempt = 0
            return
        }
        guard discoveryRetryAttempt < Self.discoveryRetryDelays.count else {
            TripDiscoveryDiagnostics.log(
                "retry budget spent ids=\(discoveryRetryIds.count) — waiting for the next re-assert"
            )
            return
        }
        let delay = Self.discoveryRetryDelays[discoveryRetryAttempt]
        discoveryRetryAttempt += 1
        let ids = Array(discoveryRetryIds)
        TripDiscoveryDiagnostics.log(
            "retry in \(Int(delay))s attempt=\(discoveryRetryAttempt)/\(Self.discoveryRetryDelays.count) "
            + "ids=\(TripDiscoveryDiagnostics.shortSessionIds(ids))"
        )
        discoveryRetryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self, self.discoveryGeneration == generation else { return }
            self.runDiscoveryPass(sessionIds: ids, generation: generation)
        }
    }

    /// A re-assert hook re-drives an exhausted retry set — but only when no retry is already
    /// scheduled, so the hydration signal a pass emits cannot drive a pass→signal→pass loop.
    private func redriveDiscoveryRetriesIfIdle() {
        guard discoveryRetryTask == nil, !discoveryRetryIds.isEmpty else { return }
        discoveryRetryAttempt = 0
        TripDiscoveryDiagnostics.log("retry re-driven by re-assert ids=\(discoveryRetryIds.count)")
        runDiscoveryPass(sessionIds: Array(discoveryRetryIds), generation: discoveryGeneration)
    }

    /// Reads the discovered trip's parent doc (already permitted for a member) to learn whether
    /// it is live, ended or cancelled. Anything else — missing doc, denied read, unknown status
    /// — is `unresolved`, i.e. retry.
    private func resolveDiscoveredStatus(sessionId: UUID) async -> DiscoveredTripStatus {
        do {
            let snapshot = try await Firestore.firestore()
                .collection("trip_sessions")
                .document(sessionId.uuidString)
                .getDocument()
            guard snapshot.exists, let data = snapshot.data() else { return .unresolved }
            switch data["canonicalStatus"] as? String {
            case TripSessionState.created.rawValue, TripSessionState.active.rawValue:
                return .live
            case TripSessionState.ended.rawValue:
                return .ended(endedAt: (data["canonicalEndedAt"] as? Timestamp)?.dateValue())
            case TripSessionState.cancelled.rawValue:
                return .cancelled
            default:
                return .unresolved
            }
        } catch {
            return .unresolved
        }
    }

    func startIncrementalListeningIfNeeded(sessionId: UUID) {
        let sid = sessionId.uuidString
        if incrementalGameListeners[sid] != nil {
            TripEndSyncDiagnostics.log("listen: already registered \(sid.prefix(8))")
            return
        }

        let db = Firestore.firestore()
        let sessionRef = db.collection("trip_sessions").document(sid)

        let listenerUserId = currentUserIdProvider()
        TripEndSyncDiagnostics.log("listen: registering \(sid.prefix(8)) as \(listenerUserId ?? "nil")")

        let gamesReg = sessionRef.collection("games").addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }
            if let error {
                Task { @MainActor in
                    self.handleListenerError(error, sessionId: sessionId, listenerUserId: listenerUserId)
                }
                return
            }
            guard let snapshot else { return }
            Task { @MainActor in
                self.applyGamesSnapshot(sessionId: sessionId, snapshot: snapshot)
            }
        }
        incrementalGameListeners[sid] = gamesReg

        let eventsReg = sessionRef.collection("activity_events").addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }
            if let error {
                Task { @MainActor in
                    self.handleListenerError(error, sessionId: sessionId, listenerUserId: listenerUserId)
                }
                return
            }
            guard let snapshot else { return }
            Task { @MainActor in
                self.applyEventsSnapshot(sessionId: sessionId, snapshot: snapshot)
            }
        }
        incrementalEventListeners[sid] = eventsReg
    }

    /// FR-69 (F-25), owner-found 2026-09-07: a listener failing with permission-denied on
    /// a session this device still holds as live is how a server-side roster removal
    /// reaches the removed device — deleting `members/{uid}` revokes its read access
    /// before the `participant_left` event could ever arrive. Both of a session's
    /// listeners fail together; the eviction apply is idempotent, so the second one is a
    /// no-op. Any other listener error is logged and otherwise ignored, as before.
    private func handleListenerError(_ error: Error, sessionId: UUID, listenerUserId: String?) {
        let nsError = error as NSError
        let permissionDenied = nsError.domain == FirestoreErrorDomain
            && nsError.code == FirestoreErrorCode.Code.permissionDenied.rawValue
        TripEndSyncDiagnostics.log(
            "listener error \(sessionId.uuidString.prefix(8)) as \(listenerUserId ?? "nil"): domain=\(nsError.domain) code=\(nsError.code) permissionDenied=\(permissionDenied) — \(nsError.localizedDescription)"
        )
        guard permissionDenied, let listenerUserId else {
            print("TripCanonicalRemoteSyncService: listener error for \(sessionId.uuidString): \(error)")
            return
        }
        removeIncrementalListeners(sessionId: sessionId)
        evictionHandler(sessionId, listenerUserId, currentUserIdProvider())
        hydrationSubject.send(sessionId)
    }

    private func applyGamesSnapshot(sessionId: UUID, snapshot: QuerySnapshot) {
        TripEndSyncDiagnostics.log("games snapshot \(sessionId.uuidString.prefix(8)): docs=\(snapshot.documents.count) fromCache=\(snapshot.metadata.isFromCache)")
        var changed = false
        for doc in snapshot.documents {
            guard let wire = TripCanonicalFirestoreFields.gameWire(documentId: doc.documentID, data: doc.data()) else { continue }
            guard let game = try? TripCanonicalMapper.domainGame(from: wire) else { continue }
            do {
                try gameInstanceRepository.upsert(instance: game)
                changed = true
            } catch {
                #if DEBUG
                print("TripCanonicalRemoteSyncService: upsert game failed \(error)")
                #endif
            }
        }
        if changed {
            do {
                try reconcileGameLifecycleFromStoredEvents(sessionId: sessionId)
            } catch {
                #if DEBUG
                print("TripCanonicalRemoteSyncService: reconcile game lifecycle after games snapshot failed \(error)")
                #endif
            }
            hydrationSubject.send(sessionId)
        }
    }

    private func applyEventsSnapshot(sessionId: UUID, snapshot: QuerySnapshot) {
        var changed = false
        var lifecycleEvents: [TripActivityEvent] = []
        var kindCounts: [String: Int] = [:]
        var unparsed = 0
        for doc in snapshot.documents {
            let data = doc.data()
            guard let wire = TripCanonicalFirestoreFields.eventWire(documentId: doc.documentID, data: data),
                  let event = TripCanonicalMapper.domainEvent(from: wire),
                  event.sessionId == sessionId else {
                unparsed += 1
                TripEndSyncDiagnostics.log("events snapshot \(sessionId.uuidString.prefix(8)): UNPARSED doc \(doc.documentID.prefix(8)) kind=\(String(describing: data["kind"])) sessionId=\(String(describing: data["sessionId"]))")
                continue
            }
            kindCounts[event.kind.rawValue, default: 0] += 1
            if event.kind == .gameStarted || event.kind == .gameEnded || event.kind == .gameCompleted {
                lifecycleEvents.append(event)
            }
            do {
                let stored = try tripActivityEventRepository.reconcileRemoteActivityEvent(event)
                if event.kind == .tripEnded {
                    TripEndSyncDiagnostics.log("events snapshot \(sessionId.uuidString.prefix(8)): trip_ended \(event.id.prefix(8)) by \(event.actorId ?? "nil") newlyStored=\(stored)")
                }
                if stored {
                    changed = true
                    if event.kind == .tripEnded {
                        let applied = try TripSessionLifecycleService.shared.applyRemoteTripEnded(
                            sessionId: sessionId,
                            endedBy: event.actorId,
                            endedAt: event.timestamp
                        )
                        TripEndSyncDiagnostics.log("events snapshot \(sessionId.uuidString.prefix(8)): trip_ended applied=\(applied) → signal \(applied ? "SENT" : "not sent")")
                        if applied {
                            tripEndedRemotelySubject.send(
                                TripEndedRemotelyInfo(sessionId: sessionId, endedBy: event.actorId)
                            )
                        }
                    }
                }
            } catch {
                TripEndSyncDiagnostics.log("events snapshot \(sessionId.uuidString.prefix(8)): reconcile \(event.kind.rawValue) \(event.id.prefix(8)) FAILED \(error)")
                #if DEBUG
                print("TripCanonicalRemoteSyncService: reconcile activity event failed \(error)")
                #endif
            }
        }
        TripEndSyncDiagnostics.log(
            "events snapshot \(sessionId.uuidString.prefix(8)): docs=\(snapshot.documents.count) fromCache=\(snapshot.metadata.isFromCache) kinds=\(kindCounts) unparsed=\(unparsed) changed=\(changed)"
        )
        for event in lifecycleEvents.sorted(by: { $0.timestamp < $1.timestamp }) {
            do {
                if try GameInstanceLifecycleService.shared.applyRemoteGameLifecycleEvent(event) {
                    changed = true
                }
            } catch {
                #if DEBUG
                print("TripCanonicalRemoteSyncService: apply game lifecycle event failed \(error)")
                #endif
            }
        }
        if changed {
            hydrationSubject.send(sessionId)
        }
    }

    private func reconcileGameLifecycleFromStoredEvents(sessionId: UUID) throws {
        let events = try tripActivityEventRepository.events(sessionId: sessionId, limit: nil)
        for event in events where event.kind == .gameStarted || event.kind == .gameEnded || event.kind == .gameCompleted {
            _ = try GameInstanceLifecycleService.shared.applyRemoteGameLifecycleEvent(event)
        }
    }

    func markTripCancelledRemote(sessionId: UUID) async throws {
        try await AppCheckReadiness.ensureCallablePrerequisites()
        let fn = functions.httpsCallable("markTripCancelledRemote")
        _ = try await fn.call((["tripSessionId": sessionId.uuidString] as [String: Any]).addingClientMetadata())
    }

    func removeParticipantAsOwner(sessionId: UUID, removedUserId: String) async throws {
        try await AppCheckReadiness.ensureCallablePrerequisites()
        let fn = functions.httpsCallable("removeTripParticipantAsOwner")
        _ = try await fn.call(([
            "tripSessionId": sessionId.uuidString,
            "removedUserId": removedUserId,
        ] as [String: Any]).addingClientMetadata())
    }

    /// True while this session holds live canonical listeners.
    func isIncrementallyListening(sessionId: UUID) -> Bool {
        incrementalGameListeners[sessionId.uuidString] != nil
    }

    func removeIncrementalListeners(sessionId: UUID) {
        let sid = sessionId.uuidString
        if incrementalGameListeners[sid] != nil {
            TripEndSyncDiagnostics.log("listen: removing \(sid.prefix(8))")
        }
        incrementalGameListeners[sid]?.remove()
        incrementalGameListeners.removeValue(forKey: sid)
        incrementalEventListeners[sid]?.remove()
        incrementalEventListeners.removeValue(forKey: sid)
    }

    func removeAllIncrementalListeners() {
        TripEndSyncDiagnostics.log("listen: removing ALL (\(incrementalGameListeners.count) session(s))")
        // §3.1.1 item 19: the account channel retires with the per-session ones — an identity
        // change or the detached-identity purge must not leave a discovery listener bound to
        // the uid that just went away.
        stopAccountTripDiscovery()
        for (_, reg) in incrementalGameListeners { reg.remove() }
        incrementalGameListeners.removeAll()
        for (_, reg) in incrementalEventListeners { reg.remove() }
        incrementalEventListeners.removeAll()
    }
}

enum TripCanonicalRemoteSyncError: Error, LocalizedError {
    case sessionNotFoundLocally
    case invalidCallableResponse

    var errorDescription: String? {
        switch self {
        case .sessionNotFoundLocally: return "Trip session not found in local store"
        case .invalidCallableResponse: return "Unexpected response from server"
        }
    }
}

// MARK: - Temporary diagnostics (trip-end propagation, owner regression 2026-09-07)

/// DEBUG-only trace of the remote trip-end path: listener re-assert → registration →
/// snapshot → local apply → recap host. Every line is prefixed `[TripEndSync]` in the Xcode
/// console and carried as `subsystem com.HammersTech.LicensePlateApp / category TripEndSync`
/// in Console.app so a device that is NOT attached to Xcode can still be read. Remove once
/// the propagation defect is closed.
enum TripEndSyncDiagnostics {
    #if DEBUG
    private static let logger = Logger(subsystem: "com.HammersTech.LicensePlateApp", category: "TripEndSync")
    #endif

    static func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        let text = message()
        logger.notice("\(text, privacy: .public)")
        print("[TripEndSync] \(text)")
        #endif
    }
}
