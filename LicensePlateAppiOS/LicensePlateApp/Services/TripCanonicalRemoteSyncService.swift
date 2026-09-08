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
        guard !isCloudSyncHeld, !isIdentityDetached,
              let userId, !userId.isEmpty,
              let authenticatedUserId, authenticatedUserId == userId else {
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
    private let functions: Functions

    private var incrementalGameListeners: [String: ListenerRegistration] = [:]
    private var incrementalEventListeners: [String: ListenerRegistration] = [:]

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
        functions: Functions = Functions.functions()
    ) {
        self.tripSessionRepository = tripSessionRepository
        self.gameInstanceRepository = gameInstanceRepository
        self.tripActivityEventRepository = tripActivityEventRepository
        self.functions = functions
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

    func bootstrapMemberSession(sessionId: UUID) async throws {
        try await AppCheckReadiness.ensureCallablePrerequisites()
        let fn = functions.httpsCallable("fetchTripBootstrapForMember")
        let result = try await fn.call((["tripSessionId": sessionId.uuidString] as [String: Any]).addingClientMetadata())
        guard let data = result.data as? [String: Any] else {
            throw TripCanonicalRemoteSyncError.invalidCallableResponse
        }
        let bundle = try TripCanonicalSyncJSON.decodeBootstrap(any: data)

        let domainSession = TripCanonicalMapper.domainSession(from: bundle.session)
        try tripSessionRepository.save(session: domainSession)

        let domainGames: [GameInstance] = try bundle.games.map { try TripCanonicalMapper.domainGame(from: $0) }
        try gameInstanceRepository.replaceGamesForSession(sessionId: sessionId, instances: domainGames)

        let domainEvents: [TripActivityEvent] = bundle.events.compactMap { TripCanonicalMapper.domainEvent(from: $0) }
        try tripActivityEventRepository.importEventsIfAbsent(domainEvents)
        try reconcileGameLifecycleFromStoredEvents(sessionId: sessionId)

        hydrationSubject.send(sessionId)
        startIncrementalListeningIfNeeded(sessionId: sessionId)
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
