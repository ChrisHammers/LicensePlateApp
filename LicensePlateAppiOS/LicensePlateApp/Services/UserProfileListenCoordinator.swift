//
//  UserProfileListenCoordinator.swift
//  LicensePlateApp
//
//  Pins Firestore `users/{uid}` snapshot listeners for self + an active trip roster and merges
//  updates into SwiftData via `UserRepository` (same path as explicit refresh).
//

import Foundation
import FirebaseFirestore

@MainActor
final class UserProfileListenCoordinator {
    static let shared = UserProfileListenCoordinator()

    private let db = Firestore.firestore()
    private var listeners: [String: ListenerRegistration] = [:]
    private var pinnedUserIds: Set<String> = []

    private init() {}

    /// Updates pinned listeners to exactly `selfUserId` ∪ `rosterUserIds` (empty ids ignored).
    func setPinnedUsers(selfUserId: String?, rosterUserIds: Set<String>) {
        var desired: Set<String> = []
        if let selfUserId, !selfUserId.isEmpty {
            desired.insert(selfUserId)
        }
        desired.formUnion(rosterUserIds.filter { !$0.isEmpty })

        for id in pinnedUserIds.subtracting(desired) {
            listeners[id]?.remove()
            listeners[id] = nil
        }

        pinnedUserIds = desired

        for id in desired {
            guard listeners[id] == nil else { continue }
            let ref = db.collection("users").document(id)
            listeners[id] = ref.addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    #if DEBUG
                    print("UserProfileListenCoordinator listener error for \(id): \(error)")
                    #endif
                    return
                }
                guard let snapshot, snapshot.exists, let data = snapshot.data() else { return }
                // COPPA FR-19: latency-compensated snapshots (local cache, or our own
                // unacknowledged write) merge profile fields but must not resolve the
                // child projection — a missing flag there means "unknown", not "adult".
                let isServerResolved = ChildFlagIngestPolicy.mayIngest(
                    isFromCache: snapshot.metadata.isFromCache,
                    hasPendingWrites: snapshot.metadata.hasPendingWrites
                )
                Task { @MainActor in
                    do {
                        try await UserRepository.shared.mergeRemoteUserDocument(
                            userId: id,
                            data: data,
                            isServerResolved: isServerResolved
                        )
                    } catch {
                        #if DEBUG
                        print("UserProfileListenCoordinator merge failed for \(id): \(error)")
                        #endif
                    }
                }
            }
        }
    }

    func stopAll() {
        for (_, reg) in listeners {
            reg.remove()
        }
        listeners.removeAll()
        pinnedUserIds.removeAll()
    }
}
