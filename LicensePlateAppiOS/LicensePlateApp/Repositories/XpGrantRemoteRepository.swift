//
//  XpGrantRemoteRepository.swift
//  LicensePlateApp
//
//  Firestore listener for `user_progression/{uid}/xp_grants` (read-only; writes via Cloud Functions).
//
//  §3.1.1 item 12 (2026-09-16): this is the only layer allowed to know Firestore's cache/server
//  distinction, so the "did the SERVER confirm this binding yet" watermark lives here.
//  `hasReceivedInitialSnapshot` keeps its exact old meaning ("a callback happened") for
//  XpDisplayedTotalResolver / XpProgressViewModel / ProgressionXpDriftAfterSyncReporter;
//  `hasReceivedServerSnapshot` is the new, stricter signal the XP toast seals its history on.
//

import Combine
import Foundation
import FirebaseFirestore

@MainActor
final class XpGrantRemoteRepository: ObservableObject {

    static let shared = XpGrantRemoteRepository()

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private(set) var boundUserId: String?

    /// Bumped on every bind and on every teardown of a live binding. Two uses: a callback from a
    /// torn-down binding is dropped instead of clobbering the new binding's grants (the callback
    /// hops through `Task { @MainActor }` and can outlive `listener?.remove()`), and the XP toast
    /// keys its remote history line on `<uid>#<generation>` so a stop/start re-arms by construction.
    private(set) var bindingGeneration = 0

    @Published private(set) var grants: [UserXpGrant] = []
    @Published private(set) var hasReceivedInitialSnapshot = false
    /// True once THIS binding has delivered a snapshot the server confirmed
    /// (`snapshot.metadata.isFromCache == false`). Never cleared by a later from-cache event —
    /// only a rebind clears it — so a mid-session network flap cannot re-open the toast watermark
    /// and swallow a grant earned during the flap. An errored listen never sets it: a denied or
    /// failed listen is not evidence about the server's grant set.
    @Published private(set) var hasReceivedServerSnapshot = false

    private init() {}

    var verifiedTotalXp: Int {
        grants.reduce(0) { $0 + $1.amount }
    }

    func startListening(userId: String) {
        guard !userId.isEmpty else { return }
        if boundUserId == userId, listener != nil { return }
        stopListening()
        bindingGeneration &+= 1
        boundUserId = userId
        hasReceivedInitialSnapshot = false
        hasReceivedServerSnapshot = false
        grants = []

        let generation = bindingGeneration
        #if DEBUG
        let boundAt = Date()
        #endif
        XpToastDiagnostics.log("bind gen=\(generation) uid=\(XpToastDiagnostics.shortUid(userId))")

        let ref = db.collection("user_progression")
            .document(userId)
            .collection("xp_grants")

        // `includeMetadataChanges: true` is required, not cosmetic. Without it a warm-cache relaunch
        // whose document set is unchanged never delivers a server-confirmed callback (the pure
        // cache→server sync-state event is suppressed), the watermark below never opens, and the
        // first genuinely new grant is absorbed instead of toasted. The FIRST raised snapshot — the
        // one that flips `hasReceivedInitialSnapshot` — is identical with and without the flag, so
        // the other readers of that flag are unaffected.
        listener = ref.addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
            Task { @MainActor in
                guard let self else { return }
                guard self.bindingGeneration == generation else {
                    XpToastDiagnostics.log(
                        "snap.stale gen=\(generation) current=\(self.bindingGeneration) dropped"
                    )
                    return
                }
                #if DEBUG
                let dtMs = Int(Date().timeIntervalSince(boundAt) * 1000)
                #else
                let dtMs = 0
                #endif
                if let error {
                    let ns = error as NSError
                    XpToastDiagnostics.log(
                        "snap.error gen=\(generation) dtMs=\(dtMs) domain=\(ns.domain) code=\(ns.code) desc=\(error.localizedDescription)"
                    )
                    // Deliberately does NOT set `hasReceivedServerSnapshot`.
                    self.hasReceivedInitialSnapshot = true
                    return
                }
                guard let snapshot else { return }
                let decoded = snapshot.documents
                    .compactMap { Self.decodeGrant(documentId: $0.documentID, data: $0.data()) }
                    .sorted { lhs, rhs in
                        let l = lhs.grantedAt ?? .distantPast
                        let r = rhs.grantedAt ?? .distantPast
                        if l != r { return l < r }
                        return lhs.grantId < rhs.grantId
                    }
                // Publish order is load-bearing: `grants` must be published before either flag, or
                // an observer woken by the flag could act on a watermark certifying a snapshot it
                // cannot yet read. The `!=` check keeps the extra metadata callbacks from churning
                // every objectWillChange subscriber.
                if decoded != self.grants {
                    self.grants = decoded
                }
                if !snapshot.metadata.isFromCache, !self.hasReceivedServerSnapshot {
                    self.hasReceivedServerSnapshot = true
                }
                if !self.hasReceivedInitialSnapshot {
                    self.hasReceivedInitialSnapshot = true
                }
                XpToastDiagnostics.log(
                    "snap gen=\(generation) fromCache=\(snapshot.metadata.isFromCache ? 1 : 0) docs=\(snapshot.documents.count) decoded=\(decoded.count) serverSealed=\(self.hasReceivedServerSnapshot ? 1 : 0) dtMs=\(dtMs)"
                )
            }
        }
    }

    func stopListening() {
        let wasBound = listener != nil || boundUserId != nil
        listener?.remove()
        listener = nil
        if wasBound {
            XpToastDiagnostics.log(
                "unbind gen=\(bindingGeneration) uid=\(XpToastDiagnostics.shortUid(boundUserId))"
            )
            // A torn-down binding must never be mistaken for a sealed one, and its in-flight
            // callback must not land on whatever binds next.
            bindingGeneration &+= 1
        }
        boundUserId = nil
        grants = []
        hasReceivedInitialSnapshot = false
        hasReceivedServerSnapshot = false
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
