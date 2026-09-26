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
//  §3.1.1 item 15 (2026-09-18): same server-confirmed watermark as XpGrantRemoteRepository
//  (item 12). This is the only layer allowed to know Firestore's cache/server distinction.
//  `hasReceivedInitialSnapshot` keeps its old meaning ("a callback delivered a snapshot") for
//  UserProgressionService / ProgressionXpDriftAfterSyncReporter; `hasReceivedServerSnapshot` is the
//  stricter signal the rank / achievement celebration seals its remote history on.
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
    /// `<uid>#<prog.identityEpoch>#<ach.identityEpoch>`: a stop/start re-earns the seal by
    /// construction, while an error-rebind of the SAME identity keeps it, so the first server gain
    /// after the outage (a peer-awarded placement crossing a rank) still celebrates instead of
    /// being absorbed as history and durably marked presented (§3.1.1 item 15, 2026-09-19).
    private(set) var identityEpoch = 0

    /// User id currently bound to `user_progression` listener (for local pending recompute).
    private(set) var currentObservedUserId: String?

    @Published private(set) var snapshot: UserProgressionSnapshot?
    /// True after the Firestore listener delivers its first snapshot for the bound user (including missing doc).
    @Published private(set) var hasReceivedInitialSnapshot = false
    /// True once this identity's listen has delivered a snapshot the server confirmed
    /// (`metadata.isFromCache == false`; a missing document counts — "no progression yet" is an
    /// answer). Never cleared by a later from-cache event and never set by an errored listen: a
    /// denied or failed listen is no evidence about the server's state. Cleared by
    /// `startListening` / `stopListening` only — a rebind after an error keeps it, exactly the way
    /// it keeps `snapshot`, and because `identityEpoch` does not move either the celebration's seal
    /// survives the outage intact.
    @Published private(set) var hasReceivedServerSnapshot = false

    private convenience init() {
        // `includeMetadataChanges: true` is required, not cosmetic: without it a warm-cache relaunch
        // whose document is unchanged never delivers a server-confirmed callback, the celebration's
        // remote seal never lands, and the first genuine server-side gain is absorbed as history.
        // The FIRST raised snapshot is identical with and without the flag.
        self.init(
            attach: { userId, onEvent in
                Firestore.firestore().collection("user_progression")
                    .document(userId)
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
        currentObservedUserId = userId
        hasReceivedInitialSnapshot = false
        hasReceivedServerSnapshot = false
        attachListener(userId: userId)
    }

    /// Shared by `startListening` and the rebind after a listen error. The rebind deliberately keeps
    /// `snapshot` and both flags: the last-known totals stay on screen through the outage, the way
    /// they do offline, instead of the displayed XP dropping to zero and climbing back.
    private func attachListener(userId: String) {
        bindingGeneration &+= 1
        let generation = bindingGeneration
        CelebrationDiagnostics.log("prog.bind gen=\(generation) uid=\(CelebrationDiagnostics.shortUid(userId))")
        listener = attach(userId) { [weak self] docSnap, error in
            Task { @MainActor in
                guard let self else { return }
                guard self.bindingGeneration == generation else {
                    CelebrationDiagnostics.log("prog.snap.stale gen=\(generation) current=\(self.bindingGeneration) dropped")
                    return
                }
                if let error {
                    Self.trace("\(userId): \(error.localizedDescription)")
                    CelebrationDiagnostics.log("prog.snap.error gen=\(generation) code=\((error as NSError).code)")
                    // Deliberately sets NEITHER flag; see `listenFailed`.
                    self.listenFailed(userId: userId, generation: generation)
                    return
                }
                guard let docSnap else { return }
                let decoded: UserProgressionSnapshot? = docSnap.exists
                    ? docSnap.data().map { Self.decodeSnapshot(data: $0) }
                    : nil
                // Publish order is load-bearing: the data before either flag, or an observer woken
                // by a flag would act on a watermark certifying a snapshot it cannot yet read. The
                // `!=` check keeps the extra metadata callbacks from churning every subscriber.
                if decoded != self.snapshot {
                    self.snapshot = decoded
                }
                if !docSnap.metadata.isFromCache {
                    if !self.hasReceivedServerSnapshot {
                        self.hasReceivedServerSnapshot = true
                    }
                    self.rebindScheduler.noteServerConfirmedSnapshot()
                }
                if !self.hasReceivedInitialSnapshot {
                    self.hasReceivedInitialSnapshot = true
                }
                CelebrationDiagnostics.log(
                    "prog.snap gen=\(generation) fromCache=\(docSnap.metadata.isFromCache ? 1 : 0) exists=\(docSnap.exists ? 1 : 0) totalXp=\(decoded?.totalXp ?? 0) serverSealed=\(self.hasReceivedServerSnapshot ? 1 : 0)"
                )
            }
        }
    }

    /// The listen is dead (see `ListenerRebindScheduler`). Release the registration so the same-uid
    /// guard in `startListening` stops mistaking it for a live one, and leave
    /// `hasReceivedInitialSnapshot` alone: an error is not a snapshot, so a binding that never
    /// delivered one stays "not hydrated" instead of reading as a hydrated, empty progression.
    /// `hasReceivedServerSnapshot` is left alone for the same reason and the inverse one — an error
    /// never sets it, and a binding that HAD been server-confirmed keeps its seal through the
    /// outage. The rebind re-attaches under the SAME `identityEpoch` (only `bindingGeneration`
    /// moves, and nothing durable is keyed on that), so the celebration's seal key is unchanged and
    /// the rebind genuinely does not re-absorb the account as history — a gain the server delivers
    /// after the rebind is a gain, not history (§3.1.1 item 15, 2026-09-19).
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
        identityEpoch &+= 1
        boundUserId = nil
        currentObservedUserId = nil
        snapshot = nil
        hasReceivedInitialSnapshot = false
        hasReceivedServerSnapshot = false
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
