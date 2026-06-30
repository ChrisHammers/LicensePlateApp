//
//  XpGrantRemoteRepository.swift
//  LicensePlateApp
//
//  Firestore listener for `user_progression/{uid}/xp_grants` (read-only; writes via Cloud Functions).
//

import Combine
import Foundation
import FirebaseFirestore

@MainActor
final class XpGrantRemoteRepository: ObservableObject {

    static let shared = XpGrantRemoteRepository()

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var boundUserId: String?

    @Published private(set) var grants: [UserXpGrant] = []
    @Published private(set) var hasReceivedInitialSnapshot = false

    private init() {}

    var verifiedTotalXp: Int {
        grants.reduce(0) { $0 + $1.amount }
    }

    func startListening(userId: String) {
        guard !userId.isEmpty else { return }
        if boundUserId == userId, listener != nil { return }
        stopListening()
        boundUserId = userId
        hasReceivedInitialSnapshot = false
        grants = []

        let ref = db.collection("user_progression")
            .document(userId)
            .collection("xp_grants")

        listener = ref.addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                guard let self else { return }
                self.hasReceivedInitialSnapshot = true
                if let error {
                    #if DEBUG
                    print("⚠️ xp_grants listener \(userId): \(error.localizedDescription)")
                    #endif
                    return
                }
                guard let snapshot else { return }
                self.grants = snapshot.documents
                    .compactMap { Self.decodeGrant(documentId: $0.documentID, data: $0.data()) }
                    .sorted { lhs, rhs in
                        let l = lhs.grantedAt ?? .distantPast
                        let r = rhs.grantedAt ?? .distantPast
                        if l != r { return l < r }
                        return lhs.grantId < rhs.grantId
                    }
            }
        }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
        boundUserId = nil
        grants = []
        hasReceivedInitialSnapshot = false
    }

    private static func decodeGrant(documentId: String, data: [String: Any]) -> UserXpGrant? {
        let amount = intValue(data["amount"])
        guard amount > 0 else { return nil }
        let grantId = (data["grantId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = (data["reason"] as? String) ?? "unknown"
        let sourceType = (data["sourceType"] as? String) ?? "unknown"
        let sourceId = (data["sourceId"] as? String) ?? documentId
        let idempotencyKey = (data["idempotencyKey"] as? String) ?? documentId
        return UserXpGrant(
            grantId: (grantId?.isEmpty == false ? grantId! : documentId),
            amount: amount,
            reason: reason,
            sourceType: sourceType,
            sourceId: sourceId,
            idempotencyKey: idempotencyKey,
            sessionId: data["sessionId"] as? String,
            achievementId: data["achievementId"] as? String,
            xpRewardAtGrant: optionalIntValue(data["xpRewardAtGrant"]),
            grantedAt: (data["grantedAt"] as? Timestamp)?.dateValue()
        )
    }

    private static func intValue(_ any: Any?) -> Int {
        if let i = any as? Int { return i }
        if let n = any as? NSNumber { return n.intValue }
        if let d = any as? Double { return Int(d) }
        return 0
    }

    private static func optionalIntValue(_ any: Any?) -> Int? {
        guard any != nil else { return nil }
        let value = intValue(any)
        return value
    }
}
