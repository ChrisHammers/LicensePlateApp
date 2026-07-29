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
}
