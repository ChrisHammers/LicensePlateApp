//
//  TripParticipationService.swift
//  LicensePlateApp
//
//  Step 14 — Non-owner voluntary leave: local pending row, roster removal, participant_left event + sync queue.
//

import Foundation

enum TripParticipationServiceError: Error, LocalizedError {
    case sessionNotFound(UUID)
    case notAParticipant
    case tripOwnerCannotLeaveViaLeaveAction
    case sessionNotActiveForLeave

    var errorDescription: String? {
        switch self {
        case .sessionNotFound(let id):
            return "Trip session not found: \(id.uuidString)"
        case .notAParticipant:
            return "You are not a participant in this trip."
        case .tripOwnerCannotLeaveViaLeaveAction:
            return "Drivers should end or delete the trip instead of leaving.".localized
        case .sessionNotActiveForLeave:
            return "This trip cannot be left in its current state."
        }
    }
}

/// FR-69 (F-25), owner-found 2026-09-07: when the server takes a member off a live
/// roster (family-exit sweep, flag-set sweep, owner kick), it deletes `members/{uid}` —
/// and that doc is exactly what `isTripSessionMember` reads, so the evicted device loses
/// READ access to the very `participant_left` event that would have told it. The only
/// signal that reaches the device is its session listeners failing with
/// permission-denied. This policy decides whether such a failure IS an eviction of the
/// local session. Fail-closed: every other explanation — signed out, a different uid
/// now signed in, the trip already over, not on the roster, or the owner (whom the
/// sweeps never remove; they end the trip instead) — leaves the local session untouched.
nonisolated enum TripEvictionDetectionPolicy {
    static func isEviction(
        sessionStatus: TripSessionState,
        listenerUserId: String,
        currentUserId: String?,
        isOwner: Bool,
        isOnRoster: Bool
    ) -> Bool {
        guard sessionStatus == .active || sessionStatus == .created else { return false }
        guard let currentUserId, currentUserId == listenerUserId else { return false }
        guard !isOwner else { return false }
        return isOnRoster
    }
}

@MainActor
protocol TripParticipationServiceProtocol: AnyObject {
    func initiateLeaveTrip(sessionId: UUID, userId: String) throws
}

@MainActor
final class TripParticipationService: TripParticipationServiceProtocol {

    static let shared = TripParticipationService(
        tripSessionRepository: TripSessionRepository.shared,
        tripActivityEventRecording: TripActivityEventRecordingService.shared,
        pendingTripLeaveRepository: PendingTripLeaveRepository.shared,
        authService: nil
    )

    private let tripSessionRepository: TripSessionRepositoryProtocol
    private let tripActivityEventRecording: TripActivityEventRecordingProtocol
    private let pendingTripLeaveRepository: PendingTripLeaveRepositoryProtocol
    private weak var authService: FirebaseAuthService?

    init(
        tripSessionRepository: TripSessionRepositoryProtocol,
        tripActivityEventRecording: TripActivityEventRecordingProtocol,
        pendingTripLeaveRepository: PendingTripLeaveRepositoryProtocol,
        authService: FirebaseAuthService?
    ) {
        self.tripSessionRepository = tripSessionRepository
        self.tripActivityEventRecording = tripActivityEventRecording
        self.pendingTripLeaveRepository = pendingTripLeaveRepository
        self.authService = authService
    }

    func bindAuthService(_ auth: FirebaseAuthService) {
        self.authService = auth
    }

    func initiateLeaveTrip(sessionId: UUID, userId: String) throws {
        guard let session = try tripSessionRepository.session(byId: sessionId) else {
            throw TripParticipationServiceError.sessionNotFound(sessionId)
        }
        guard session.status == .active || session.status == .created else {
            throw TripParticipationServiceError.sessionNotActiveForLeave
        }
        if session.createdBy == userId {
            throw TripParticipationServiceError.tripOwnerCannotLeaveViaLeaveAction
        }
        let inRoster = session.participants.contains { $0.userId == userId }
        guard inRoster else {
            throw TripParticipationServiceError.notAParticipant
        }

        let isOffline = !(authService?.isOnline ?? false)
        AnalyticsService.shared.log(.tripParticipantLeaveInitiated(tripSessionId: sessionId.uuidString, offline: isOffline))

        try pendingTripLeaveRepository.insertPending(sessionId: sessionId, userId: userId)

        do {
            try tripSessionRepository.removeParticipant(sessionId: sessionId, userId: userId)
        } catch {
            try? pendingTripLeaveRepository.deletePending(sessionId: sessionId, userId: userId)
            throw error
        }

        let event = TripActivityEvent(
            sessionId: sessionId,
            kind: .participantLeft,
            actorId: userId,
            payload: [
                TripActivityEventPayloadKey.participantId: userId,
                TripActivityEventPayloadKey.leaveReason: "voluntary",
            ]
        )
        try tripActivityEventRecording.recordForSync(event)
    }

    /// Apply a SERVER-side roster removal to the local copy (see
    /// `TripEvictionDetectionPolicy`). The server already wrote the `participant_left`
    /// event and this device can no longer read the session, so nothing is queued for
    /// sync: the roster row goes (parity with a voluntary leave) and the session is
    /// marked ended locally, so the history this device legitimately co-produced lands
    /// in the Travel Log instead of lingering as a live trip (FR-69(b)).
    /// Returns false when nothing applied — a re-run is a no-op.
    @discardableResult
    func applyServerEviction(
        sessionId: UUID,
        listenerUserId: String,
        currentUserId: String?
    ) throws -> Bool {
        guard let session = try tripSessionRepository.session(byId: sessionId) else {
            return false
        }
        let isOnRoster = session.participants.contains { $0.userId == listenerUserId }
        guard TripEvictionDetectionPolicy.isEviction(
            sessionStatus: session.status,
            listenerUserId: listenerUserId,
            currentUserId: currentUserId,
            isOwner: session.createdBy == listenerUserId,
            isOnRoster: isOnRoster
        ) else {
            return false
        }
        try tripSessionRepository.removeParticipant(sessionId: sessionId, userId: listenerUserId)
        try tripSessionRepository.updateStatus(sessionId: sessionId, status: .ended)
        return true
    }
}
