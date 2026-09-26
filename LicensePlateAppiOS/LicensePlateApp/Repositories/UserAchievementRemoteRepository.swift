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
//  §3.1.1 item 15 (2026-09-18): same per-binding server-confirmed watermark as
//  XpGrantRemoteRepository (item 12) and UserProgressionRepository — see the notes there.
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
    private(set) var boundUserId: String?
    /// Bumped on every attach and every stop, so a callback that outlives its listener (it hops
    /// through `Task { @MainActor }`) is dropped — above all a late ERROR, which would otherwise
    /// tear down the listener of whatever bound next. That stale-callback guard is its ONLY job:
    /// nothing outside this file may key durable state on it, because the error-driven rebind bumps
    /// it too (see `identityEpoch`).
    private(set) var bindingGeneration = 0

    /// Bumped only where the IDENTITY of the binding changes — `startListening` (a real (re)bind)
    /// and `stopListening` — never by `attachListener` and so never by the rebind after a listen
    /// error. The celebration keys its remote history seal on
    /// `<uid>#<prog.identityEpoch>#<ach.identityEpoch>`; see `UserProgressionRepository`.
    private(set) var identityEpoch = 0

    @Published private(set) var records: [String: UserAchievementRecord] = [:]
    @Published private(set) var hasReceivedInitialSnapshot = false
    /// True once this identity's listen has delivered a snapshot the server confirmed. Never
    /// cleared by a later from-cache event and never set by an errored listen; cleared by
    /// `startListening` / `stopListening` only, exactly like `records` (see
    /// `UserProgressionRepository`).
    @Published private(set) var hasReceivedServerSnapshot = false

    private convenience init() {
        // `includeMetadataChanges: true` is required (see UserProgressionRepository): an unchanged
        // warm cache would otherwise never deliver the server-confirmed callback the seal waits for.
        self.init(
            attach: { userId, onEvent in
                Firestore.firestore().collection("user_achievements")
                    .document(userId)
                    .collection("achievements")
                    .addSnapshotListener(includeMetadataChanges: true, listener: onEvent)
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
        identityEpoch &+= 1
        boundUserId = userId
        hasReceivedInitialSnapshot = false
        hasReceivedServerSnapshot = false
        records = [:]
        attachListener(userId: userId)
    }

    /// Shared by `startListening` and the rebind after a listen error. The rebind deliberately keeps
    /// `records` and both flags: the last-known unlocks stay in view through the outage, the way
    /// they do offline, instead of vanishing and reappearing under the celebration service.
    private func attachListener(userId: String) {
        bindingGeneration &+= 1
        let generation = bindingGeneration
        CelebrationDiagnostics.log("ach.bind gen=\(generation) uid=\(CelebrationDiagnostics.shortUid(userId))")
        listener = attach(userId) { [weak self] snapshot, error in
            Task { @MainActor in
                guard let self else { return }
                guard self.bindingGeneration == generation else {
                    CelebrationDiagnostics.log("ach.snap.stale gen=\(generation) current=\(self.bindingGeneration) dropped")
                    return
                }
                if let error {
                    Self.trace("\(userId): \(error.localizedDescription)")
                    CelebrationDiagnostics.log("ach.snap.error gen=\(generation) code=\((error as NSError).code)")
                    // Deliberately sets NEITHER flag; see `listenFailed`.
                    self.listenFailed(userId: userId, generation: generation)
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
                // Publish order is load-bearing: records → server flag → guarded initial flag. The
                // `!=` check keeps the extra metadata callbacks from churning every subscriber.
                if mapped != self.records {
                    self.records = mapped
                }
                if !snapshot.metadata.isFromCache {
                    if !self.hasReceivedServerSnapshot {
                        self.hasReceivedServerSnapshot = true
                    }
                    self.rebindScheduler.noteServerConfirmedSnapshot()
                }
                if !self.hasReceivedInitialSnapshot {
                    self.hasReceivedInitialSnapshot = true
                }
                CelebrationDiagnostics.log(
                    "ach.snap gen=\(generation) fromCache=\(snapshot.metadata.isFromCache ? 1 : 0) docs=\(snapshot.documents.count) serverSealed=\(self.hasReceivedServerSnapshot ? 1 : 0)"
                )
            }
        }
    }

    /// The listen is dead (see `ListenerRebindScheduler`). Release the registration so the same-uid
    /// guard in `startListening` stops mistaking it for a live one, and leave
    /// `hasReceivedInitialSnapshot` alone: an error is not a snapshot, so a binding that never
    /// delivered one stays "no remote records yet" instead of reading as a confirmed empty set.
    /// `hasReceivedServerSnapshot` is left alone for the same reason and the inverse one — an error
    /// never sets it, and a binding that HAD been server-confirmed keeps its seal through the
    /// outage. The rebind re-attaches under the SAME `identityEpoch` (only `bindingGeneration`
    /// moves), so the celebration's seal key is unchanged and the rebind genuinely does not
    /// re-absorb the account's unlocks as history (§3.1.1 item 15, 2026-09-19).
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
        identityEpoch &+= 1
        boundUserId = nil
        records = [:]
        hasReceivedInitialSnapshot = false
        hasReceivedServerSnapshot = false
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
