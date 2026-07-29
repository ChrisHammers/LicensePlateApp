//
//  TripParticipantPrefsStore.swift
//  LicensePlateApp
//
//  Local cache + Firestore fetch/upsert for per-trip participant prefs.
//

import Foundation
import Combine
import FirebaseFirestore
import FirebaseFunctions

@MainActor
protocol TripParticipantPrefsReading: AnyObject {
    func prefs(sessionId: UUID, userId: String) -> TripParticipantPrefs
}

@MainActor
final class TripParticipantPrefsStore: ObservableObject, TripParticipantPrefsReading {
    static let shared = TripParticipantPrefsStore()

    /// Bumped when any cached prefs change so views can refresh.
    @Published private(set) var revision: Int = 0

    private var cache: [String: TripParticipantPrefs] = [:]
    private let defaults: UserDefaults
    private let db: Firestore
    private let functions: Functions

    init(
        defaults: UserDefaults = .standard,
        db: Firestore = Firestore.firestore(),
        functions: Functions = Functions.functions()
    ) {
        self.defaults = defaults
        self.db = db
        self.functions = functions
    }

    private func cacheKey(sessionId: UUID, userId: String) -> String {
        "tripParticipantPrefs.\(sessionId.uuidString).\(userId)"
    }

    func prefs(sessionId: UUID, userId: String) -> TripParticipantPrefs {
        let key = cacheKey(sessionId: sessionId, userId: userId)
        if let cached = cache[key] {
            return cached
        }
        if let data = defaults.dictionary(forKey: key) {
            let parsed = TripParticipantPrefs.fromFirestoreMap(data)
            cache[key] = parsed
            return parsed
        }
        return .default
    }

    func apply(sessionId: UUID, userId: String, prefs: TripParticipantPrefs) {
        let key = cacheKey(sessionId: sessionId, userId: userId)
        cache[key] = prefs
        var stored: [String: Any] = prefs.callablePrefsMap
        stored["source"] = prefs.source.rawValue
        defaults.set(stored, forKey: key)
        revision += 1
    }

    func resetForSignOut() {
        cache.removeAll()
        revision += 1
    }

    /// Load from Firestore; if missing, use fallback and optionally backfill via upsert.
    func load(
        sessionId: UUID,
        userId: String,
        fallback: TripParticipantPrefs = .default,
        backfillIfMissing: Bool = true
    ) async {
        guard !userId.isEmpty else { return }
        let ref = db.collection("trip_sessions").document(sessionId.uuidString)
            .collection("participant_prefs").document(userId)
        do {
            let snap = try await ref.getDocument()
            if snap.exists, let data = snap.data() {
                apply(sessionId: sessionId, userId: userId, prefs: TripParticipantPrefs.fromFirestoreMap(data))
                return
            }
            apply(sessionId: sessionId, userId: userId, prefs: fallback)
            if backfillIfMissing {
                await saveLocalAndRemote(sessionId: sessionId, userId: userId, prefs: fallback)
            }
        } catch {
            if cache[cacheKey(sessionId: sessionId, userId: userId)] == nil {
                apply(sessionId: sessionId, userId: userId, prefs: fallback)
            }
        }
    }

    func saveLocalAndRemote(sessionId: UUID, userId: String, prefs: TripParticipantPrefs) async {
        let edited = TripParticipantPrefs(
            skipVoiceConfirmation: prefs.skipVoiceConfirmation,
            saveLocationWhenMarkingPlates: prefs.saveLocationWhenMarkingPlates,
            showMyLocationOnLargeMap: prefs.showMyLocationOnLargeMap,
            trackMyLocationDuringTrip: prefs.trackMyLocationDuringTrip,
            source: .userEdit
        )
        apply(sessionId: sessionId, userId: userId, prefs: edited)
        do {
            let fn = functions.httpsCallable("upsertTripParticipantPrefs")
            _ = try await fn.call(([
                "tripSessionId": sessionId.uuidString,
                "prefs": edited.callablePrefsMap
            ] as [String: Any]).addingClientMetadata())
        } catch {
            // Keep optimistic local cache; next online load may reconcile.
        }
    }
}
