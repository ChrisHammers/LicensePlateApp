//
//  UserAchievementRemoteRepository.swift
//  LicensePlateApp
//
//  Firestore listener for `user_achievements/{uid}/achievements` (read-only; writes via Cloud Functions).
//
//  Listen errors (2026-09-18): an errored listen no longer sets `hasReceivedInitialSnapshot`, and
//  because Firestore never raises another event on a listener that errored, the repository
//  releases the dead registration and rebinds itself on a bounded backoff
//  (`ListenerRebindScheduler`).
//

import Combine
import Foundation
import FirebaseFirestore

@MainActor
final class UserAchievementRemoteRepository: ObservableObject {

    static let shared = UserAchievementRemoteRepository()

    /// Attaches the `achievements` listener for a uid. A seam only: handing in a fake pins the
    /// listen lifecycle (an error never latches, the rebind is bounded) without a backend.
    typealias Attach = (
        _ userId: String,
        _ onEvent: @escaping (QuerySnapshot?, Error?) -> Void
    ) -> ListenerRegistration

    private let attach: Attach
    private let rebindScheduler: ListenerRebindScheduler
    private var listener: ListenerRegistration?
    private var boundUserId: String?
    /// Bumped on every attach and every stop, so a callback that outlives its listener (it hops
    /// through `Task { @MainActor }`) is dropped — above all a late ERROR, which would otherwise
    /// tear down the listener of whatever bound next.
    private var bindingGeneration = 0

    @Published private(set) var records: [String: UserAchievementRecord] = [:]
    @Published private(set) var hasReceivedInitialSnapshot = false

    private convenience init() {
        self.init(
            attach: { userId, onEvent in
                Firestore.firestore().collection("user_achievements")
                    .document(userId)
                    .collection("achievements")
                    .addSnapshotListener(onEvent)
            },
            rebindScheduler: ListenerRebindScheduler()
        )
    }

    init(attach: @escaping Attach, rebindScheduler: ListenerRebindScheduler) {
        self.attach = attach
        self.rebindScheduler = rebindScheduler
    }

    func startListening(userId: String) {
        guard !userId.isEmpty else { return }
        if boundUserId == userId, listener != nil { return }
        stopListening()
        boundUserId = userId
        hasReceivedInitialSnapshot = false
        records = [:]
        attachListener(userId: userId)
    }

    /// Shared by `startListening` and the rebind after a listen error. The rebind deliberately keeps
    /// `records` and the flag: the last-known unlocks stay in view through the outage, the way they
    /// do offline, instead of vanishing and reappearing under the celebration service.
    private func attachListener(userId: String) {
        bindingGeneration &+= 1
        let generation = bindingGeneration
        listener = attach(userId) { [weak self] snapshot, error in
            Task { @MainActor in
                guard let self, self.bindingGeneration == generation else { return }
                if let error {
                    Self.trace("\(userId): \(error.localizedDescription)")
                    self.listenFailed(userId: userId, generation: generation)
                    return
                }
                guard let snapshot else { return }
                self.hasReceivedInitialSnapshot = true
                if !snapshot.metadata.isFromCache {
                    self.rebindScheduler.noteServerConfirmedSnapshot()
                }
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

    /// The listen is dead (see `ListenerRebindScheduler`). Release the registration so the same-uid
    /// guard in `startListening` stops mistaking it for a live one, and leave
    /// `hasReceivedInitialSnapshot` alone: an error is not a snapshot, so a binding that never
    /// delivered one stays "no remote records yet" instead of reading as a confirmed empty set.
    private func listenFailed(userId: String, generation: Int) {
        listener?.remove()
        listener = nil
        let delay = rebindScheduler.scheduleRebind { [weak self] in
            // A stop or a uid change in the meantime bumped the generation: that binding wins.
            guard let self, self.bindingGeneration == generation else { return }
            self.attachListener(userId: userId)
        }
        Self.trace("\(userId): \(ListenerRebindScheduler.describe(delay))")
    }

    private static func trace(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("⚠️ user_achievements listener \(message())")
        #endif
    }

    func stopListening() {
        rebindScheduler.reset()
        listener?.remove()
        listener = nil
        bindingGeneration &+= 1
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
