//
//  CompetitiveSupersedeCanonicalDiscovery.swift
//  LicensePlateApp
//
//  When the server supersedes a late competitive find, it returns only `discovery_rejected` to the client.
//  Local replay uses `region_found` / `region_removed` for standings and checked rows, so we materialize
//  the canonical first finder’s `region_found` from rejection payload fields (parity with Firestore).
//

import Foundation

enum CompetitiveSupersedeCanonicalDiscovery {

    /// Builds the winning `region_found` event described by server rejection metadata, if complete.
    static func regionFoundEvent(from rejection: TripActivityEvent) -> TripActivityEvent? {
        guard rejection.kind == .discoveryRejected,
              let p = rejection.payload,
              let regionId = p[TripActivityEventPayloadKey.regionId], !regionId.isEmpty,
              let gameInstanceId = p[TripActivityEventPayloadKey.gameInstanceId], !gameInstanceId.isEmpty,
              let eventId = p[TripActivityEventPayloadKey.firstFinderEventId], !eventId.isEmpty,
              let finderPid = p[TripActivityEventPayloadKey.firstFinderParticipantId], !finderPid.isEmpty,
              let atSecStr = p[TripActivityEventPayloadKey.firstFinderDiscoveredAt],
              let atSec = TimeInterval(atSecStr) else {
            return nil
        }
        var pl: [String: String] = [
            TripActivityEventPayloadKey.regionId: regionId,
            TripActivityEventPayloadKey.gameInstanceId: gameInstanceId,
            TripActivityEventPayloadKey.participantId: finderPid,
        ]
        if let im = p[TripActivityEventPayloadKey.inputMethod], !im.isEmpty {
            pl[TripActivityEventPayloadKey.inputMethod] = im
        }
        return TripActivityEvent(
            id: eventId,
            sessionId: rejection.sessionId,
            kind: .regionFound,
            timestamp: Date(timeIntervalSince1970: atSec),
            actorId: finderPid,
            payload: pl
        )
    }
}
