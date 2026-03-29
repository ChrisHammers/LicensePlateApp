//
//  TripCanonicalRemoteSyncService.swift
//  LicensePlateApp
//
//  Step 12.5 — Publish local trip canonical state to Firestore (callable) and bootstrap/joiner incremental sync.
//

import Combine
import Foundation
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
        ])
        // Creators never call `bootstrapMemberSession`; without listeners they miss peers’ `activity_events`.
        startIncrementalListeningIfNeeded(sessionId: sessionId)
    }

    func appendEventToRemote(_ event: TripActivityEvent) async throws -> GameplayEventAppendOutcome {
        let wire = TripCanonicalMapper.wireEvent(from: event)
        let eventObj = try TripCanonicalSyncJSON.jsonObject(encodable: wire)
        let fn = functions.httpsCallable("appendTripActivityEvent")
        let result = try await fn.call([
            "tripSessionId": event.sessionId.uuidString,
            "event": eventObj,
        ])
        return try GameplayAppendCallableResponseParser.outcome(from: result.data, uploadedEventId: event.id)
    }

    func bootstrapMemberSession(sessionId: UUID) async throws {
        let fn = functions.httpsCallable("fetchTripBootstrapForMember")
        let result = try await fn.call(["tripSessionId": sessionId.uuidString])
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

        hydrationSubject.send(sessionId)
        startIncrementalListeningIfNeeded(sessionId: sessionId)
    }

    func startIncrementalListeningIfNeeded(sessionId: UUID) {
        let sid = sessionId.uuidString
        if incrementalGameListeners[sid] != nil { return }

        let db = Firestore.firestore()
        let sessionRef = db.collection("trip_sessions").document(sid)

        let gamesReg = sessionRef.collection("games").addSnapshotListener { [weak self] snapshot, error in
            guard let self, error == nil, let snapshot else { return }
            Task { @MainActor in
                self.applyGamesSnapshot(sessionId: sessionId, snapshot: snapshot)
            }
        }
        incrementalGameListeners[sid] = gamesReg

        let eventsReg = sessionRef.collection("activity_events").addSnapshotListener { [weak self] snapshot, error in
            guard let self, error == nil, let snapshot else { return }
            Task { @MainActor in
                self.applyEventsSnapshot(sessionId: sessionId, snapshot: snapshot)
            }
        }
        incrementalEventListeners[sid] = eventsReg
    }

    private func applyGamesSnapshot(sessionId: UUID, snapshot: QuerySnapshot) {
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
            hydrationSubject.send(sessionId)
        }
    }

    private func applyEventsSnapshot(sessionId: UUID, snapshot: QuerySnapshot) {
        var changed = false
        for doc in snapshot.documents {
            let data = doc.data()
            guard let wire = TripCanonicalFirestoreFields.eventWire(documentId: doc.documentID, data: data),
                  let event = TripCanonicalMapper.domainEvent(from: wire),
                  event.sessionId == sessionId else { continue }
            do {
                if try tripActivityEventRepository.reconcileRemoteActivityEvent(event) {
                    changed = true
                }
            } catch {
                #if DEBUG
                print("TripCanonicalRemoteSyncService: reconcile activity event failed \(error)")
                #endif
            }
        }
        if changed {
            hydrationSubject.send(sessionId)
        }
    }

    func markTripCancelledRemote(sessionId: UUID) async throws {
        let fn = functions.httpsCallable("markTripCancelledRemote")
        _ = try await fn.call(["tripSessionId": sessionId.uuidString])
    }

    func removeParticipantAsOwner(sessionId: UUID, removedUserId: String) async throws {
        let fn = functions.httpsCallable("removeTripParticipantAsOwner")
        _ = try await fn.call([
            "tripSessionId": sessionId.uuidString,
            "removedUserId": removedUserId,
        ])
    }

    func removeIncrementalListeners(sessionId: UUID) {
        let sid = sessionId.uuidString
        incrementalGameListeners[sid]?.remove()
        incrementalGameListeners.removeValue(forKey: sid)
        incrementalEventListeners[sid]?.remove()
        incrementalEventListeners.removeValue(forKey: sid)
    }

    func removeAllIncrementalListeners() {
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
