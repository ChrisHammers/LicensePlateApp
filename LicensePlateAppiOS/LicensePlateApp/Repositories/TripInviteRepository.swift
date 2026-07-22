//
//  TripInviteRepository.swift
//  LicensePlateApp
//
//  Step 04 — Trip invites. Step 08 — Firestore-authoritative mirror + Cloud Functions.
//

import Combine
import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import SwiftData

// MARK: - Firestore → domain mapping (unit-tested via dict helper)

enum TripInviteFirestoreMapper {
    /// Maps Firestore `trip_invites` document data; `documentId` is the canonical invite id.
    static func tripInvite(documentId: String, data: [String: Any]) -> TripInvite? {
        guard let tripSessionId = data["tripSessionId"] as? String, !tripSessionId.isEmpty,
              let tripName = data["tripName"] as? String,
              let fromUserId = data["fromUserId"] as? String,
              let toUserId = data["toUserId"] as? String
        else {
            return nil
        }

        let statusRaw = (data["status"] as? String) ?? TripInvite.TripInviteStatus.pending.rawValue
        let status = TripInvite.TripInviteStatus(rawValue: statusRaw) ?? .pending

        let createdAt = timestampDate(data["createdAt"]) ?? Date()
        let expiresAt = timestampDate(data["expiresAt"]) ?? createdAt.addingTimeInterval(86400 * 7)
        let respondedAt = timestampDate(data["respondedAt"])

        return TripInvite(
            inviteId: documentId,
            tripSessionId: tripSessionId,
            tripName: tripName,
            fromUserId: fromUserId,
            toUserId: toUserId,
            status: status,
            createdAt: createdAt,
            expiresAt: expiresAt,
            respondedAt: respondedAt
        )
    }

    static func timestampDate(_ value: Any?) -> Date? {
        if let ts = value as? Timestamp {
            return ts.dateValue()
        }
        return nil
    }
}

@MainActor
final class TripInviteRepository: ObservableObject, TripInviteRepositoryProtocol {

    static let shared = TripInviteRepository()

    private let db = Firestore.firestore()
    private var modelContext: ModelContext?
    nonisolated(unsafe) private var inviteListeners: [ListenerRegistration] = []
    /// Listener registrations keyed by `tripSessionId`; accessed from MainActor handlers and `stopListening`.
    nonisolated(unsafe) private var memberListeners: [String: ListenerRegistration] = [:]
    /// Per-session member count after last Firestore `members` snapshot (for `participantJoinedTrip` deltas).
    private var lastMemberDocCountBySession: [String: Int] = [:]
    /// First snapshot per session establishes baseline without logging join (avoids noise on initial listener attach).
    private var memberSnapshotBaselineApplied: Set<String> = []

    private let inviteSnapshotSubject = PassthroughSubject<Void, Never>()
    var inviteSnapshotSignal: AnyPublisher<Void, Never> {
        inviteSnapshotSubject.eraseToAnyPublisher()
    }

    private let tripSessionRepository: TripSessionRepository
    private let pendingTripLeaveRepository: PendingTripLeaveRepositoryProtocol

    @Published private(set) var tripInvites: [TripInvite] = []

    init(
        tripSessionRepository: TripSessionRepository = .shared,
        pendingTripLeaveRepository: PendingTripLeaveRepositoryProtocol = PendingTripLeaveRepository.shared
    ) {
        self.tripSessionRepository = tripSessionRepository
        self.pendingTripLeaveRepository = pendingTripLeaveRepository
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    // MARK: - Listening

    func startListening(userId: String) {
        stopListening()

        let incomingQuery = db.collection("trip_invites")
            .whereField("toUserId", isEqualTo: userId)

        let inc = incomingQuery.addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                self?.handleInviteSnapshot(snapshot: snapshot, error: error, userId: userId)
            }
        }
        inviteListeners.append(inc)

        let outgoingQuery = db.collection("trip_invites")
            .whereField("fromUserId", isEqualTo: userId)

        let out = outgoingQuery.addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                self?.handleInviteSnapshot(snapshot: snapshot, error: error, userId: userId)
            }
        }
        inviteListeners.append(out)
    }

    nonisolated func stopListening() {
        for listener in inviteListeners {
            listener.remove()
        }
        inviteListeners.removeAll()
        for (_, reg) in memberListeners {
            reg.remove()
        }
        memberListeners.removeAll()
        Task { @MainActor in
            TripCanonicalRemoteSyncService.shared.removeAllIncrementalListeners()
        }
    }

    private func handleInviteSnapshot(snapshot: QuerySnapshot?, error: Error?, userId: String) {
        if error != nil {
            return
        }
        guard let snapshot, let ctx = modelContext else { return }

        for document in snapshot.documents {
            guard let invite = TripInviteFirestoreMapper.tripInvite(
                documentId: document.documentID,
                data: document.data()
            ) else { continue }

            let searchId = invite.inviteId
            var descriptor = FetchDescriptor<TripInvite>(
                predicate: #Predicate<TripInvite> { $0.inviteId == searchId }
            )
            descriptor.fetchLimit = 1

            if let existing = try? ctx.fetch(descriptor).first {
                existing.tripSessionId = invite.tripSessionId
                existing.tripName = invite.tripName
                existing.fromUserId = invite.fromUserId
                existing.toUserId = invite.toUserId
                existing.status = invite.status
                existing.createdAt = invite.createdAt
                existing.expiresAt = invite.expiresAt
                existing.respondedAt = invite.respondedAt
            } else {
                ctx.insert(invite)
            }
        }

        try? ctx.save()
        refreshPublishedInvites(userId: userId)
        reconcileMemberListeners(userId: userId)
        inviteSnapshotSubject.send()
    }

    // MARK: - Member listeners (roster merge)

    private func reconcileMemberListeners(userId: String) {
        guard modelContext != nil else { return }

        let outgoingSessions = tripInvites
            .filter { $0.fromUserId == userId }
            .map(\.tripSessionId)
        let acceptedIncomingSessions = tripInvites
            .filter { $0.toUserId == userId && $0.statusEnum == .accepted }
            .map(\.tripSessionId)
        let sessionIds = Set(outgoingSessions + acceptedIncomingSessions)

        for id in memberListeners.keys where !sessionIds.contains(id) {
            memberListeners[id]?.remove()
            memberListeners.removeValue(forKey: id)
            if let uuid = UUID(uuidString: id) {
                TripCanonicalRemoteSyncService.shared.removeIncrementalListeners(sessionId: uuid)
            }
        }

        for sessionId in sessionIds where memberListeners[sessionId] == nil {
            let reg = db.collection("trip_sessions")
                .document(sessionId)
                .collection("members")
                .addSnapshotListener { [weak self] snap, _ in
                    Task { @MainActor in
                        self?.handleMembersSnapshot(sessionId: sessionId, snapshot: snap)
                    }
                }
            memberListeners[sessionId] = reg
        }
    }

    private func handleMembersSnapshot(sessionId: String, snapshot: QuerySnapshot?) {
        guard let snapshot, let sessionUUID = UUID(uuidString: sessionId) else { return }

        Task { @MainActor in
            if (try? tripSessionRepository.session(byId: sessionUUID)) == nil {
                do {
                    try await TripCanonicalRemoteSyncService.shared.bootstrapMemberSession(sessionId: sessionUUID)
                } catch {
                    #if DEBUG
                    print("TripInviteRepository: bootstrapMemberSession failed: \(error)")
                    #endif
                }
            }

            let currentUid = Auth.auth().currentUser?.uid
            var mergedParticipants: [TripParticipant] = []
            mergedParticipants.reserveCapacity(snapshot.documents.count)
            for doc in snapshot.documents {
                let memberUserId = doc.documentID
                if let me = currentUid, memberUserId == me {
                    if (try? pendingTripLeaveRepository.hasPending(sessionId: sessionUUID, userId: me)) == true {
                        continue
                    }
                }
                let data = doc.data()
                let roleStr = (data["role"] as? String) ?? "member"
                let role = TripParticipantRole(rawValue: roleStr) ?? .member
                let joinedAt = TripInviteFirestoreMapper.timestampDate(data["joinedAt"]) ?? Date()
                mergedParticipants.append(TripParticipant(userId: memberUserId, role: role, joinedAt: joinedAt))
            }
            mergedParticipants.sort { $0.userId < $1.userId }

            if var session = try? tripSessionRepository.session(byId: sessionUUID) {
                session.participants = mergedParticipants
                do {
                    try tripSessionRepository.save(session: session)
                } catch {
                    #if DEBUG
                    print("TripInviteRepository: save session after members merge failed: \(error)")
                    #endif
                }
            }

            let remoteMemberIds = Set(snapshot.documents.map(\.documentID))
            if let me = currentUid,
               memberSnapshotBaselineApplied.contains(sessionId),
               !snapshot.metadata.hasPendingWrites,
               !remoteMemberIds.contains(me) {
                try? pendingTripLeaveRepository.deletePending(sessionId: sessionUUID, userId: me)
                AnalyticsService.shared.log(.tripParticipantLeaveReconciled(tripSessionId: sessionId))
            }

            let newCount = snapshot.documents.count
            if !memberSnapshotBaselineApplied.contains(sessionId) {
                memberSnapshotBaselineApplied.insert(sessionId)
                lastMemberDocCountBySession[sessionId] = newCount
            } else {
                let previous = lastMemberDocCountBySession[sessionId] ?? newCount
                lastMemberDocCountBySession[sessionId] = newCount
                if newCount > previous {
                    let participantCountAfterJoin = (try? tripSessionRepository.session(byId: sessionUUID))?.participants.count ?? newCount
                    AnalyticsService.shared.log(.participantJoinedTrip(
                        tripId: sessionId,
                        participantCountAfterJoin: participantCountAfterJoin,
                        teamCountAfterJoin: nil
                    ))
                }
            }
        }
    }

    // MARK: - Queries

    func getIncomingInvites(userId: String) throws -> [TripInvite] {
        guard let ctx = modelContext else { throw TripInviteRepositoryError.noModelContext }
        let searchUserId = userId
        let pending = TripInvite.TripInviteStatus.pending.rawValue
        var descriptor = FetchDescriptor<TripInvite>(
            predicate: #Predicate<TripInvite> { invite in
                invite.toUserId == searchUserId && invite.status == pending
            }
        )
        descriptor.sortBy = [SortDescriptor(\.createdAt, order: .reverse)]
        return try ctx.fetch(descriptor)
    }

    func getOutgoingInvites(userId: String) throws -> [TripInvite] {
        guard let ctx = modelContext else { throw TripInviteRepositoryError.noModelContext }
        let searchUserId = userId
        let pending = TripInvite.TripInviteStatus.pending.rawValue
        let legacySent = TripInvite.TripInviteStatus.sent.rawValue
        // TODO(step-08-cleanup): Remove legacy `.sent` fallback once all local-only invite rows are migrated/expired.
        var descriptor = FetchDescriptor<TripInvite>(
            predicate: #Predicate<TripInvite> { invite in
                invite.fromUserId == searchUserId && (invite.status == pending || invite.status == legacySent)
            }
        )
        descriptor.sortBy = [SortDescriptor(\.createdAt, order: .reverse)]
        return try ctx.fetch(descriptor)
    }

    func getInvites(forTripSessionId tripSessionId: String) throws -> [TripInvite] {
        guard let ctx = modelContext else { throw TripInviteRepositoryError.noModelContext }
        let searchTripSessionId = tripSessionId
        var descriptor = FetchDescriptor<TripInvite>(
            predicate: #Predicate<TripInvite> { invite in
                invite.tripSessionId == searchTripSessionId
            }
        )
        descriptor.sortBy = [SortDescriptor(\.createdAt, order: .reverse)]
        return try ctx.fetch(descriptor)
    }

    func hasPendingInvite(tripSessionId: String, toUserId: String) throws -> Bool {
        guard let ctx = modelContext else { throw TripInviteRepositoryError.noModelContext }
        let searchTripSessionId = tripSessionId
        let searchToUserId = toUserId
        let pending = TripInvite.TripInviteStatus.pending.rawValue
        var descriptor = FetchDescriptor<TripInvite>(
            predicate: #Predicate<TripInvite> { invite in
                invite.tripSessionId == searchTripSessionId && invite.toUserId == searchToUserId && invite.status == pending
            }
        )
        descriptor.fetchLimit = 1
        return try ctx.fetch(descriptor).first != nil
    }

    // MARK: - Cloud Functions

    func acceptInvite(inviteId: String, userId: String) async throws {
        try await respondToTripInvite(inviteId: inviteId, accept: true)
    }

    func declineInvite(inviteId: String, userId: String) async throws {
        try await respondToTripInvite(inviteId: inviteId, accept: false)
    }

    private func respondToTripInvite(inviteId: String, accept: Bool) async throws {
        guard Auth.auth().currentUser != nil else {
            throw TripInviteRepositoryError.notAuthenticated
        }

        let functions = Functions.functions()
        let fn = functions.httpsCallable("respondToTripInvite")
        _ = try await fn.call(([
            "inviteId": inviteId,
            "response": accept ? "accept" : "decline",
        ] as [String: Any]).addingClientMetadata())
    }

    func cancelInvite(inviteId: String, userId: String) async throws {
        guard Auth.auth().currentUser != nil else {
            throw TripInviteRepositoryError.notAuthenticated
        }

        let functions = Functions.functions()
        let fn = functions.httpsCallable("cancelTripInvite")
        _ = try await fn.call(([
            "inviteId": inviteId,
        ] as [String: Any]).addingClientMetadata())
    }

    func sendTripInvite(
        tripSessionId: String,
        tripName: String,
        fromUserId: String,
        toUserId: String,
        expiresAt: Date?
    ) async throws -> String {
        guard let uid = Auth.auth().currentUser?.uid, uid == fromUserId else {
            throw TripInviteRepositoryError.notAuthenticated
        }

        var payload: [String: Any] = [
            "toUserId": toUserId,
            "tripSessionId": tripSessionId,
            "tripName": tripName,
            "method": "search",
        ]
        if let expiresAt {
            payload["expiresAtMs"] = Int64(expiresAt.timeIntervalSince1970 * 1000)
        }

        let functions = Functions.functions()
        let fn = functions.httpsCallable("sendTripInvite")
        let result = try await fn.call(payload.addingClientMetadata())

        guard let data = result.data as? [String: Any],
              let inviteId = data["inviteId"] as? String else {
            throw TripInviteRepositoryError.invalidServerResponse
        }

        return inviteId
    }

    /// Refresh the published list for a user (incoming + outgoing).
    func refreshPublishedInvites(userId: String) {
        guard let ctx = modelContext else { return }
        let searchUserId = userId
        var descriptor = FetchDescriptor<TripInvite>(
            predicate: #Predicate<TripInvite> { invite in
                invite.fromUserId == searchUserId || invite.toUserId == searchUserId
            }
        )
        descriptor.sortBy = [SortDescriptor(\.createdAt, order: .reverse)]
        tripInvites = (try? ctx.fetch(descriptor)) ?? []
    }

    /// Hard sign-out: wipe trip invites and stop listeners (also clears trip incremental sync).
    func deleteAllLocal() throws {
        stopListening()
        guard let ctx = modelContext else {
            tripInvites = []
            return
        }
        try ctx.delete(model: TripInvite.self)
        try ctx.save()
        tripInvites = []
    }

    deinit {
        stopListening()
    }
}

enum TripInviteRepositoryError: Error, LocalizedError {
    case noModelContext
    case inviteNotFound(String)
    case notRecipient
    case notSender
    case notAuthenticated
    case invalidServerResponse

    var errorDescription: String? {
        switch self {
        case .noModelContext: return "Model context not set"
        case .inviteNotFound(let id): return "Trip invite not found: \(id)"
        case .notRecipient: return "User is not the recipient of this invite"
        case .notSender: return "User is not the sender of this invite"
        case .notAuthenticated: return "You must be signed in"
        case .invalidServerResponse: return "Unexpected response from server"
        }
    }
}
