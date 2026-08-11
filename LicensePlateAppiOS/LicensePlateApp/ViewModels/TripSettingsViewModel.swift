//
//  TripSettingsViewModel.swift
//  LicensePlateApp
//
//  Step 6.9.3.1 — Trip-level settings (name, start/end/delete) + viewer participant location prefs.
//

import Foundation
import Combine

@MainActor
final class TripSettingsViewModel: ObservableObject {

    @Published private(set) var currentSession: TripSession
    @Published private(set) var errorMessage: String?
    @Published private(set) var shouldPresentTripLimitPaywall = false
    @Published var participantPrefs: TripParticipantPrefs

    let sessionId: UUID

    private let tripSessionRepository: TripSessionRepositoryProtocol
    private let lifecycleService: TripSessionLifecycleServiceProtocol
    private let tripEntitlementGate: TripEntitlementGate
    private let authService: FirebaseAuthService
    private let participationService: TripParticipationServiceProtocol
    private let prefsStore: TripParticipantPrefsStore
    private let appPrefsStore: AppPrefsStore

    var viewerUserId: String {
        authService.currentUser?.firebaseUID ?? authService.currentUser?.id ?? ""
    }

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
        participationService: TripParticipationServiceProtocol = TripParticipationService.shared,
        prefsStore: TripParticipantPrefsStore = .shared,
        appPrefsStore: AppPrefsStore = .shared
    ) {
        self.sessionId = session.id
        self.currentSession = session
        self.tripSessionRepository = tripSessionRepository
        self.lifecycleService = lifecycleService
        self.tripEntitlementGate = tripEntitlementGate
        self.authService = authService
        self.participationService = participationService
        self.prefsStore = prefsStore
        self.appPrefsStore = appPrefsStore
        let uid = authService.currentUser?.firebaseUID ?? authService.currentUser?.id ?? ""
        self.participantPrefs = prefsStore.prefs(sessionId: session.id, userId: uid)
    }

    /// Load remote prefs (backfill missing docs from account defaults).
    func loadParticipantPrefs() async {
        let uid = viewerUserId
        guard !uid.isEmpty else { return }
        let fallback = appPrefsStore.participationDefaults.asParticipantPrefs()
        await prefsStore.load(
            sessionId: sessionId,
            userId: uid,
            fallback: fallback,
            backfillIfMissing: true
        )
        participantPrefs = prefsStore.prefs(sessionId: sessionId, userId: uid)
    }

    func persistParticipantPrefs() {
        let uid = viewerUserId
        guard !uid.isEmpty else { return }
        var edited = participantPrefs
        edited.source = .userEdit
        participantPrefs = edited
        prefsStore.apply(sessionId: sessionId, userId: uid, prefs: edited)
        Task {
            await prefsStore.saveLocalAndRemote(
                sessionId: sessionId,
                userId: uid,
                prefs: edited
            )
        }
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
            // COPPA F-7 (FR-34, owner UX): the sheet slot always presents; child
            // sessions render the informational variant (no purchase UI) there.
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
