//
//  TripSettingsViewModel.swift
//  LicensePlateApp
//
//  Step 6.9.3.1 — Trip-level settings only (name, start/end/delete trip). No game or SwiftData in views.
//

import Foundation
import Combine

@MainActor
final class TripSettingsViewModel: ObservableObject {

    @Published private(set) var currentSession: TripSession
    @Published private(set) var errorMessage: String?
    @Published private(set) var shouldPresentTripLimitPaywall = false

    let sessionId: UUID

    private let tripSessionRepository: TripSessionRepositoryProtocol
    private let lifecycleService: TripSessionLifecycleServiceProtocol
    private let tripEntitlementGate: TripEntitlementGate
    private let authService: FirebaseAuthService
    private let participationService: TripParticipationServiceProtocol

    var isTripCreator: Bool {
        let currentUserID = authService.currentUser?.firebaseUID ?? authService.currentUser?.id
        guard let id = currentUserID else { return false }
        return currentSession.createdBy == id
    }

    /// Step 14 — Passengers can leave; owners use end/delete trip.
    var canLeaveTrip: Bool {
        guard !isTripCreator else { return false }
        let uid = authService.currentUser?.firebaseUID ?? authService.currentUser?.id
        guard let uid else { return false }
        guard currentSession.status == .active || currentSession.status == .created else { return false }
        return currentSession.participants.contains { $0.userId == uid }
    }

    init(
        session: TripSession,
        tripSessionRepository: TripSessionRepositoryProtocol,
        lifecycleService: TripSessionLifecycleServiceProtocol,
        authService: FirebaseAuthService,
        tripEntitlementGate: TripEntitlementGate = .shared,
        participationService: TripParticipationServiceProtocol = TripParticipationService.shared
    ) {
        self.sessionId = session.id
        self.currentSession = session
        self.tripSessionRepository = tripSessionRepository
        self.lifecycleService = lifecycleService
        self.tripEntitlementGate = tripEntitlementGate
        self.authService = authService
        self.participationService = participationService
    }

    func refreshSession() {
        if let session = try? tripSessionRepository.session(byId: sessionId) {
            currentSession = session
        }
    }

    func startTrip() throws {
        let actorId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id ?? ""
        shouldPresentTripLimitPaywall = false
        do {
            try tripEntitlementGate.validateCanStartTrip(
                user: authService.currentUser,
                userId: actorId,
                sessionId: sessionId
            )
        } catch let error as TripEntitlementGateError {
            shouldPresentTripLimitPaywall = true
            throw error
        }
        try lifecycleService.startTrip(sessionId: sessionId, actorId: actorId)
        refreshSession()
    }

    func endTrip() throws {
        let endedBy = authService.currentUser?.firebaseUID ?? authService.currentUser?.id
        try lifecycleService.endTrip(sessionId: sessionId, endedBy: endedBy)
        refreshSession()
    }

    /// Cancels the trip session (UI: Delete trip); clears games and events via `TripSessionLifecycleService`.
    func deleteTrip() throws {
        let cancelledBy = authService.currentUser?.firebaseUID ?? authService.currentUser?.id
        try lifecycleService.cancelSession(sessionId: sessionId, cancelledBy: cancelledBy)
        refreshSession()
    }

    /// Step 14 — Voluntary leave for non-owners; queues `participant_left` sync.
    func leaveTrip() throws {
        let uid = authService.currentUser?.firebaseUID ?? authService.currentUser?.id ?? ""
        try participationService.initiateLeaveTrip(sessionId: sessionId, userId: uid)
        refreshSession()
    }

    func setError(_ message: String) {
        errorMessage = message
        objectWillChange.send()
    }

    func dismissTripLimitPaywall() {
        shouldPresentTripLimitPaywall = false
    }

    func clearError() {
        errorMessage = nil
        objectWillChange.send()
    }

    func updateTripName(_ name: String) {
        currentSession.name = name
        objectWillChange.send()
        do {
            try tripSessionRepository.save(session: currentSession)
        } catch {
            errorMessage = error.localizedDescription
            AnalyticsService.shared.log(.persistenceSaveFailed(context: "trip_settings_name", error: error.localizedDescription))
            objectWillChange.send()
        }
    }

    func saveSession() {
        objectWillChange.send()
        do {
            try tripSessionRepository.save(session: currentSession)
        } catch {
            errorMessage = error.localizedDescription
            AnalyticsService.shared.log(.persistenceSaveFailed(context: "trip_settings_save", error: error.localizedDescription))
            objectWillChange.send()
        }
    }
}
