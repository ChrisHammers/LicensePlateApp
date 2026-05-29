//
//  FairnessAckWatermarkRemoteService.swift
//  LicensePlateApp
//
//  Step 13.2 — Read/write per-user fairness ack watermark under games/{id}/fairness_ack_watermarks/{uid}.
//

import Foundation
import FirebaseFirestore
import FirebaseFunctions

@MainActor
final class FairnessAckWatermarkRemoteService {

    static let shared = FairnessAckWatermarkRemoteService()

    private let db = Firestore.firestore()
    private let functions: Functions

    init(functions: Functions = Functions.functions()) {
        self.functions = functions
    }

    func fetchWatermark(tripSessionId: UUID, gameInstanceId: UUID, userId: String) async throws -> Date? {
        let ref = db.collection("trip_sessions").document(tripSessionId.uuidString)
            .collection("games").document(gameInstanceId.uuidString)
            .collection("fairness_ack_watermarks").document(userId)
        let snap = try await ref.getDocument()
        guard snap.exists, let ts = snap.get("lastAckAt") as? Timestamp else { return nil }
        return ts.dateValue()
    }

    func pushWatermark(tripSessionId: UUID, gameInstanceId: UUID, lastAckAt: Date) async throws {
        let fn = functions.httpsCallable("updateFairnessAckWatermark")
        _ = try await fn.call([
            "tripSessionId": tripSessionId.uuidString,
            "gameInstanceId": gameInstanceId.uuidString,
            "lastAckAtSeconds": lastAckAt.timeIntervalSince1970,
        ].addingClientMetadata())
    }
}
