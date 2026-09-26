//
//  UserProgressionRepository.swift
//  LicensePlateApp
//
//  Step 16 — Firestore listener for `user_progression` (read-only; writes via Cloud Functions).
//
//  Listen errors (2026-09-18): an errored listen no longer sets `hasReceivedInitialSnapshot` (it
//  used to, with `snapshot` still nil — "hydrated, 0 XP"), and because Firestore never raises
//  another event on a listener that errored, the repository releases the dead registration and
//  rebinds itself on a bounded backoff (`ListenerRebindScheduler`).
//

import Combine
import Foundation
import FirebaseFirestore

@MainActor
final class UserProgressionRepository: ObservableObject {

    static let shared = UserProgressionRepository()

    /// Attaches the `user_progression/{uid}` listener. A seam only: handing in a fake pins the
    /// listen lifecycle (an error never latches, the rebind is bounded) without a backend.
    typealias Attach = (
        _ userId: String,
        _ onEvent: @escaping (DocumentSnapshot?, Error?) -> Void
    ) -> ListenerRegistration

    private let attach: Attach
    private let rebindScheduler: ListenerRebindScheduler
    private var listener: ListenerRegistration?
    private var boundUserId: String?
    /// Bumped on every attach and every stop, so a callback that outlives its listener (it hops
    /// through `Task { @MainActor }`) is dropped — above all a late ERROR, which would otherwise
    /// tear down the listener of whatever bound next.
    private var bindingGeneration = 0

    /// User id currently bound to `user_progression` listener (for local pending recompute).
    private(set) var currentObservedUserId: String?

    @Published private(set) var snapshot: UserProgressionSnapshot?
    /// True after the Firestore listener delivers its first snapshot for the bound user (including missing doc).
    @Published private(set) var hasReceivedInitialSnapshot = false

    private convenience init() {
        self.init(
            attach: { userId, onEvent in
                Firestore.firestore().collection("user_progression")
                    .document(userId)
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
        currentObservedUserId = userId
        hasReceivedInitialSnapshot = false
        attachListener(userId: userId)
    }

    /// Shared by `startListening` and the rebind after a listen error. The rebind deliberately keeps
    /// `snapshot` and the flag: the last-known totals stay on screen through the outage, the way
    /// they do offline, instead of the displayed XP dropping to zero and climbing back.
    private func attachListener(userId: String) {
        bindingGeneration &+= 1
        let generation = bindingGeneration
        listener = attach(userId) { [weak self] docSnap, error in
            Task { @MainActor in
                guard let self, self.bindingGeneration == generation else { return }
                if let error {
                    Self.trace("\(userId): \(error.localizedDescription)")
                    self.listenFailed(userId: userId, generation: generation)
                    return
                }
                guard let docSnap else { return }
                self.hasReceivedInitialSnapshot = true
                if !docSnap.metadata.isFromCache {
                    self.rebindScheduler.noteServerConfirmedSnapshot()
                }
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

    /// The listen is dead (see `ListenerRebindScheduler`). Release the registration so the same-uid
    /// guard in `startListening` stops mistaking it for a live one, and leave
    /// `hasReceivedInitialSnapshot` alone: an error is not a snapshot, so a binding that never
    /// delivered one stays "not hydrated" instead of reading as a hydrated, empty progression.
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
        print("⚠️ user_progression listener \(message())")
        #endif
    }

    func stopListening() {
        rebindScheduler.reset()
        listener?.remove()
        listener = nil
        bindingGeneration &+= 1
        boundUserId = nil
        currentObservedUserId = nil
        snapshot = nil
        hasReceivedInitialSnapshot = false
    }

    private static func decodeSnapshot(data: [String: Any]) -> UserProgressionSnapshot {
        let totalXp = intValue(data["totalXp"])
        let acceptedRegionFindCount = intValue(data["acceptedRegionFindCount"])
        let competitiveFirstPlaceFinishes = intValue(data["competitiveFirstPlaceFinishes"])
        let everCompetitiveFirstPlace = boolValue(data["everCompetitiveFirstPlace"])
        let lastUpdatedAt = (data["lastUpdatedAt"] as? Timestamp)?.dateValue()
        let appliedIds: Set<String> = {
            guard let raw = data["appliedProgressionEvents"] as? [String: Any] else { return [] }
            return Set(raw.keys)
        }()
        let appliedScopes: Set<String> = {
            guard let raw = data["appliedProgressionScopes"] as? [String: Any] else { return [] }
            return Set(raw.keys)
        }()
        return UserProgressionSnapshot(
            totalXp: totalXp,
            acceptedRegionFindCount: acceptedRegionFindCount,
            competitiveFirstPlaceFinishes: competitiveFirstPlaceFinishes,
            everCompetitiveFirstPlace: everCompetitiveFirstPlace,
            lastUpdatedAt: lastUpdatedAt,
            appliedProgressionEventIds: appliedIds,
            appliedProgressionScopeKeys: appliedScopes
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
