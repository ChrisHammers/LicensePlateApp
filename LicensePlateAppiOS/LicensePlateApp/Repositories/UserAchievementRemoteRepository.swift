//
//  UserAchievementRemoteRepository.swift
//  LicensePlateApp
//
//  Firestore listener for `user_achievements/{uid}/achievements` (read-only; writes via Cloud Functions).
//

import Combine
import Foundation
import FirebaseFirestore

@MainActor
final class UserAchievementRemoteRepository: ObservableObject {

    static let shared = UserAchievementRemoteRepository()

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var boundUserId: String?

    @Published private(set) var records: [String: UserAchievementRecord] = [:]
    @Published private(set) var hasReceivedInitialSnapshot = false

    private init() {}

    func startListening(userId: String) {
        guard !userId.isEmpty else { return }
        if boundUserId == userId, listener != nil { return }
        stopListening()
        boundUserId = userId
        hasReceivedInitialSnapshot = false
        records = [:]

        let ref = db.collection("user_achievements")
            .document(userId)
            .collection("achievements")

        listener = ref.addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                guard let self else { return }
                self.hasReceivedInitialSnapshot = true
                if let error {
                    #if DEBUG
                    print("⚠️ user_achievements listener \(userId): \(error.localizedDescription)")
                    #endif
                    return
                }
                guard let snapshot else { return }
                var mapped: [String: UserAchievementRecord] = [:]
                for doc in snapshot.documents {
                    let data = doc.data()
                    let achievementId = (data["achievementId"] as? String) ?? doc.documentID
                    let lastProgress = Self.intValue(data["lastProgress"])
                    let unlockedAt = (data["unlockedAt"] as? Timestamp)?.dateValue() ?? .now
                    mapped[achievementId] = UserAchievementRecord(
                        userId: userId,
                        achievementId: achievementId,
                        unlockedAt: unlockedAt,
                        lastProgress: lastProgress,
                        isBackfilled: false,
                        storedXpReward: Self.optionalIntValue(data["xpReward"])
                    )
                }
                self.records = mapped
            }
        }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
        boundUserId = nil
        records = [:]
        hasReceivedInitialSnapshot = false
    }

    private static func intValue(_ any: Any?) -> Int {
        if let i = any as? Int { return i }
        if let n = any as? NSNumber { return n.intValue }
        if let d = any as? Double { return Int(d) }
        return 0
    }

    private static func optionalIntValue(_ any: Any?) -> Int? {
        guard any != nil else { return nil }
        return intValue(any)
    }
}
