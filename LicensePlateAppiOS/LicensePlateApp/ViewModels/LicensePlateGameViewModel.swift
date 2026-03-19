//
//  LicensePlateGameViewModel.swift
//  LicensePlateApp
//
//  Step 6.8 — ViewModel for license plate game screen (game-level only).
//

import Foundation
import Combine

/// Result of submitting a discovery (mark found).
enum DiscoverySubmitResult {
    case success
    case rejectedDuplicate(message: String)
    case failure(Error)
}

@MainActor
final class LicensePlateGameViewModel: ObservableObject {

    @Published private(set) var currentSession: TripSession
    @Published private(set) var foundRegions: [FoundRegion] = []
    @Published var rejectedDuplicateMessage: String?
    @Published private(set) var errorMessage: String?

    let sessionId: UUID
    let game: GameInstance

    private let tripSessionRepository: TripSessionRepositoryProtocol
    private let gameInstanceRepository: GameInstanceRepositoryProtocol
    private let tripActivityEventRepository: TripActivityEventRepositoryProtocol
    private let lifecycleService: TripSessionLifecycleServiceProtocol
    private let syncCoordinator: SyncCoordinatorProtocol
    private let authService: FirebaseAuthService

    var isTripCreator: Bool {
        let currentUserID = authService.currentUser?.firebaseUID ?? authService.currentUser?.id
        guard let id = currentUserID else { return false }
        return currentSession.createdBy == id
    }

    var isTripActive: Bool {
        currentSession.startedAt != nil && currentSession.status != .ended
    }

    init(
        session: TripSession,
        game: GameInstance,
        tripSessionRepository: TripSessionRepositoryProtocol,
        gameInstanceRepository: GameInstanceRepositoryProtocol,
        tripActivityEventRepository: TripActivityEventRepositoryProtocol,
        lifecycleService: TripSessionLifecycleServiceProtocol,
        syncCoordinator: SyncCoordinatorProtocol,
        authService: FirebaseAuthService
    ) {
        self.currentSession = session
        self.sessionId = session.id
        self.game = game
        self.tripSessionRepository = tripSessionRepository
        self.gameInstanceRepository = gameInstanceRepository
        self.tripActivityEventRepository = tripActivityEventRepository
        self.lifecycleService = lifecycleService
        self.syncCoordinator = syncCoordinator
        self.authService = authService
        self.foundRegions = (try? tripActivityEventRepository.foundRegions(sessionId: session.id, gameInstanceId: game.id)) ?? []
    }

    func refreshSession() {
        if let session = try? tripSessionRepository.session(byId: sessionId) {
            currentSession = session
        }
    }

    func refreshFoundRegions() {
        foundRegions = (try? tripActivityEventRepository.foundRegions(sessionId: sessionId, gameInstanceId: game.id)) ?? []
    }

    func startTrip() throws {
        let actorId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id ?? ""
        try lifecycleService.startTrip(sessionId: sessionId, actorId: actorId)
        refreshSession()
    }

    func endTrip() throws {
        let endedBy = authService.currentUser?.firebaseUID ?? authService.currentUser?.id
        try lifecycleService.endTrip(sessionId: sessionId, endedBy: endedBy)
        refreshSession()
    }

    func resetTrip() throws {
        try lifecycleService.resetTrip(sessionId: sessionId, gameInstanceId: game.id)
        refreshSession()
        refreshFoundRegions()
        foundRegions = []
    }

    func cancelTrip() throws {
        let cancelledBy = authService.currentUser?.firebaseUID ?? authService.currentUser?.id
        try lifecycleService.cancelSession(sessionId: sessionId, cancelledBy: cancelledBy)
        refreshSession()
    }

    func submitDiscovery(regionID: String, inputMethod: FoundRegion.InputMethod) -> DiscoverySubmitResult {
        let participantId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id ?? ""
        let discoveries = (try? tripActivityEventRepository.discoveries(sessionId: sessionId, gameInstanceId: game.id)) ?? []
        let byTarget = Dictionary(grouping: discoveries, by: \.targetId)
        let existingDiscoveriesForTarget = byTarget[regionID] ?? []

        let result = DiscoveryRulesEngine.evaluateDiscoverySubmission(
            mode: game.commonConfig.gameMode,
            existingDiscoveriesForTarget: existingDiscoveriesForTarget,
            candidateParticipantId: participantId,
            candidateTargetId: regionID,
            gameInstanceId: game.id,
            inputMethod: inputMethod,
            occurredAt: Date(),
            riskContext: nil
        )

        if result.outcome == .rejectedDuplicate {
            rejectedDuplicateMessage = "Only the first finder gets credit in competitive mode.".localized
            AnalyticsService.shared.log(.discoveryRejectedDuplicate(
                tripId: sessionId.uuidString,
                gameInstanceId: game.id.uuidString,
                targetId: regionID,
                participantId: participantId.isEmpty ? nil : participantId,
                mode: game.commonConfig.gameMode.rawValue
            ))
            return .rejectedDuplicate(message: rejectedDuplicateMessage ?? "")
        }

        guard result.shouldAppendEvent else {
            return .success
        }

        var payload: [String: String] = [
            TripActivityEventPayloadKey.regionId: regionID,
            TripActivityEventPayloadKey.gameInstanceId: game.id.uuidString,
            TripActivityEventPayloadKey.participantId: participantId,
            TripActivityEventPayloadKey.inputMethod: inputMethod.rawValue
        ]
        let event = TripActivityEvent(
            sessionId: sessionId,
            kind: .regionFound,
            actorId: participantId.isEmpty ? nil : participantId,
            payload: payload
        )
        do {
            try tripActivityEventRepository.append(event)
            try? syncCoordinator.enqueueForSync(sessionId: sessionId, eventId: event.id)
            refreshFoundRegions()
            rejectedDuplicateMessage = nil
            AnalyticsService.shared.log(.discoveryOutcomeRecorded(
                tripId: sessionId.uuidString,
                gameInstanceId: game.id.uuidString,
                targetId: regionID,
                outcome: result.outcome.rawValue,
                participantId: participantId.isEmpty ? nil : participantId
            ))
            return .success
        } catch {
            AnalyticsService.shared.log(.persistenceSaveFailed(context: "trip_tracker_discovery", error: error.localizedDescription))
            return .failure(error)
        }
    }

    func removeDiscovery(regionID: String) {
        var payload: [String: String] = [
            TripActivityEventPayloadKey.regionId: regionID,
            TripActivityEventPayloadKey.gameInstanceId: game.id.uuidString
        ]
        let event = TripActivityEvent(sessionId: sessionId, kind: .regionRemoved, payload: payload)
        do {
            try tripActivityEventRepository.append(event)
            try? syncCoordinator.enqueueForSync(sessionId: sessionId, eventId: event.id)
            let participantId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id
            AnalyticsService.shared.log(.discoveryUnfind(
                tripId: sessionId.uuidString,
                gameInstanceId: game.id.uuidString,
                targetId: regionID,
                participantId: participantId
            ))
            refreshFoundRegions()
        } catch {
            errorMessage = error.localizedDescription
            AnalyticsService.shared.log(.persistenceSaveFailed(context: "trip_tracker_unfind", error: error.localizedDescription))
            objectWillChange.send()
        }
    }

    func clearRejectedDuplicateMessage() {
        rejectedDuplicateMessage = nil
    }

    func setError(_ message: String) {
        errorMessage = message
        objectWillChange.send()
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
            AnalyticsService.shared.log(.persistenceSaveFailed(context: "trip_tracker_settings", error: error.localizedDescription))
            objectWillChange.send()
        }
    }

    func setEnabledCountries(_ countries: [PlateRegion.Country]) {
        currentSession.enabledCountries = countries
        objectWillChange.send()
        do {
            try tripSessionRepository.save(session: currentSession)
        } catch {
            errorMessage = error.localizedDescription
            AnalyticsService.shared.log(.persistenceSaveFailed(context: "trip_tracker_settings", error: error.localizedDescription))
            objectWillChange.send()
        }
    }

    func saveSession() {
        objectWillChange.send()
        do {
            try tripSessionRepository.save(session: currentSession)
        } catch {
            errorMessage = error.localizedDescription
            AnalyticsService.shared.log(.persistenceSaveFailed(context: "trip_tracker_settings", error: error.localizedDescription))
            objectWillChange.send()
        }
    }
}
