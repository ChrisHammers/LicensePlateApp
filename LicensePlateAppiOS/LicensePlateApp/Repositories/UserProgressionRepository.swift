//
//  UserProgressionRepository.swift
//  LicensePlateApp
//
//  Step 16 — Firestore listener for `user_progression` (read-only; writes via Cloud Functions).
//

import Combine
import Foundation
import FirebaseFirestore

@MainActor
final class UserProgressionRepository: ObservableObject {

    static let shared = UserProgressionRepository()

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var boundUserId: String?

    @Published private(set) var snapshot: UserProgressionSnapshot?

    private init() {}

    func startListening(userId: String) {
        guard !userId.isEmpty else { return }
        if boundUserId == userId, listener != nil { return }
        stopListening()
        boundUserId = userId

        let ref = db.collection("user_progression").document(userId)
        listener = ref.addSnapshotListener { [weak self] docSnap, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    #if DEBUG
                    print("⚠️ user_progression listener \(userId): \(error.localizedDescription)")
                    #endif
                    return
                }
                guard let docSnap else { return }
                if !docSnap.exists {
                    self.snapshot = nil
                    return
                }
                guard let data = docSnap.data() else {
                    self.snapshot = nil
                    return
                }
                self.snapshot = Self.decodeSnapshot(data: data)
            }
        }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
        boundUserId = nil
        snapshot = nil
    }

    private static func decodeSnapshot(data: [String: Any]) -> UserProgressionSnapshot {
        let totalXp = intValue(data["totalXp"])
        let acceptedRegionFindCount = intValue(data["acceptedRegionFindCount"])
        let competitiveFirstPlaceFinishes = intValue(data["competitiveFirstPlaceFinishes"])
        let everCompetitiveFirstPlace = boolValue(data["everCompetitiveFirstPlace"])
        let lastUpdatedAt = (data["lastUpdatedAt"] as? Timestamp)?.dateValue()
        return UserProgressionSnapshot(
            totalXp: totalXp,
            acceptedRegionFindCount: acceptedRegionFindCount,
            competitiveFirstPlaceFinishes: competitiveFirstPlaceFinishes,
            everCompetitiveFirstPlace: everCompetitiveFirstPlace,
            lastUpdatedAt: lastUpdatedAt
        )
    }

    private static func intValue(_ any: Any?) -> Int {
        if let i = any as? Int { return i }
        if let n = any as? NSNumber { return n.intValue }
        if let d = any as? Double { return Int(d) }
        return 0
    }

    private static func boolValue(_ any: Any?) -> Bool {
        if let b = any as? Bool { return b }
        if let n = any as? NSNumber { return n.boolValue }
        return false
    }
}
