//
//  GameplayEventSyncModels.swift
//  LicensePlateApp
//
//  Step 13 — Callable `appendTripActivityEvent` response + fairness UI payload.
//

import Foundation

/// Outcome of syncing one gameplay event to the cloud resolver.
enum GameplayEventAppendOutcome: Sendable {
    case accepted
    /// Local optimistic `region_found` was not written remotely; server authored `srvrej_*` rejection.
    case superseded(localRegionFoundEventId: String, serverRejection: TripActivityEvent)
}

/// Emitted after local DB reconciliation so the game VM can show fairness messaging.
struct FairnessResolutionInfo: Sendable, Equatable {
    var tripSessionId: UUID
    var gameInstanceId: UUID
    var tripSessionName: String
    var regionId: String
    var firstFinderParticipantId: String
    var rejectionReasonRaw: String
    /// Firestore / sync path dedupe for the same server `discovery_rejected` doc.
    var sourceRejectionEventId: String?
}

extension FairnessResolutionInfo {
    /// Builds from a server-authored `discovery_rejected` (callable supersede or listener merge).
    init?(rejection: TripActivityEvent, sessionId: UUID, tripSessionName: String) {
        guard rejection.kind == .discoveryRejected,
              let gidStr = rejection.payload?[TripActivityEventPayloadKey.gameInstanceId],
              let gid = UUID(uuidString: gidStr),
              let regionId = rejection.payload?[TripActivityEventPayloadKey.regionId],
              let reason = rejection.payload?[TripActivityEventPayloadKey.rejectionReason] else {
            return nil
        }
        let firstFinder = rejection.payload?[TripActivityEventPayloadKey.firstFinderParticipantId] ?? ""
        guard reason == DiscoveryRejectionReason.serverRejectedLateCompetitive.rawValue
            || reason == DiscoveryRejectionReason.rejectedInvalidParticipant.rawValue
            || reason == DiscoveryRejectionReason.serverRejectedSupersededByEarlierTimestamp.rawValue else {
            return nil
        }
        self.tripSessionId = sessionId
        self.gameInstanceId = gid
        self.tripSessionName = tripSessionName
        self.regionId = regionId
        self.firstFinderParticipantId = firstFinder
        self.rejectionReasonRaw = reason
        self.sourceRejectionEventId = rejection.id
    }
}

enum GameplayAppendCallableResponseParser {

    /// Parses HTTPS callable result dictionary (best-effort; legacy servers return only `success`).
    static func outcome(from data: Any?, uploadedEventId: String) throws -> GameplayEventAppendOutcome {
        guard let dict = data as? [String: Any], (dict["success"] as? Bool) == true else {
            throw TripCanonicalRemoteSyncError.invalidCallableResponse
        }
        let resolution = dict["resolution"] as? String ?? "accepted"
        if resolution == "superseded" {
            guard let rejAny = dict["rejectionEvent"] else {
                throw TripCanonicalRemoteSyncError.invalidCallableResponse
            }
            let rejection = try decodeRejectionEvent(from: rejAny)
            return .superseded(localRegionFoundEventId: uploadedEventId, serverRejection: rejection)
        }
        return .accepted
    }

    static func decodeRejectionEvent(from any: Any) throws -> TripActivityEvent {
        guard let normalized = normalizeEventJSONObject(any) else {
            throw TripCanonicalRemoteSyncError.invalidCallableResponse
        }
        let json = try JSONSerialization.data(withJSONObject: normalized)
        let dto = try JSONDecoder().decode(TripActivityEventWireDTO.self, from: json)
        guard let event = TripCanonicalMapper.domainEvent(from: dto) else {
            throw TripCanonicalRemoteSyncError.invalidCallableResponse
        }
        return event
    }

    /// Coerce Firestore/Obj-C nested maps into JSON-friendly `[String: Any]` with string payload values.
    private static func normalizeEventJSONObject(_ any: Any) -> [String: Any]? {
        guard var top = any as? [String: Any] else { return nil }
        if let payload = top["payload"] {
            if let p = payload as? [String: String] {
                top["payload"] = p
            } else if let p = payload as? [String: Any] {
                top["payload"] = p.mapValues { v in
                    if let s = v as? String { return s }
                    if v is NSNull { return "" }
                    return String(describing: v)
                }
            } else if payload is NSNull {
                top["payload"] = [String: String]()
            }
        }
        return top
    }
}
