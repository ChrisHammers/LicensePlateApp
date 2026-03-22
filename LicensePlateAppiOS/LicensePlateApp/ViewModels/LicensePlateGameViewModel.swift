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
    /// Solo trip but another participant already credited for this target — invalid attribution (client + server should enforce).
    case rejectedInvalidParticipant(message: String)
    case failure(Error)
}

@MainActor
final class LicensePlateGameViewModel: ObservableObject {

    @Published private(set) var currentSession: TripSession
    /// Latest persisted game instance (refresh after lifecycle or config changes).
    @Published private(set) var game: GameInstance
    @Published private(set) var foundRegions: [FoundRegion] = []
    @Published var rejectedDuplicateMessage: String?
    @Published var rejectedInvalidParticipantMessage: String?
    @Published private(set) var errorMessage: String?
    /// Editable license-plate scope while Game Settings sheet is open; persisted when user taps Done.
    @Published private(set) var licensePlateScopeDraft: LicensePlateScopeSettingsDraft?

    let sessionId: UUID

    private let tripSessionRepository: TripSessionRepositoryProtocol
    private let gameInstanceRepository: GameInstanceRepositoryProtocol
    private let tripActivityEventRepository: TripActivityEventRepositoryProtocol
    private let lifecycleService: TripSessionLifecycleServiceProtocol
    private let gameInstanceLifecycleService: GameInstanceLifecycleServiceProtocol
    private let tripActivityEventRecording: TripActivityEventRecordingProtocol
    private let authService: FirebaseAuthService

    var isTripCreator: Bool {
        let currentUserID = authService.currentUser?.firebaseUID ?? authService.currentUser?.id
        guard let id = currentUserID else { return false }
        return currentSession.createdBy == id
    }

    /// Trip container is in progress (user has started the trip).
    var isTripContainerActive: Bool {
        currentSession.status == .active && currentSession.startedAt != nil
    }

    /// License plate play is allowed: active trip and this game’s lifecycle is `.started`.
    var isGamePlayActive: Bool {
        isTripContainerActive && game.commonConfig.lifecycleState == .started
    }

    /// Games on this trip (for optional “remove this game” when the trip has multiple).
    var tripGameInstanceCount: Int {
        (try? gameInstanceRepository.gameCount(sessionId: sessionId)) ?? 0
    }

    /// Creator only; trip not ended/cancelled; at least two games so one can be removed.
    var canRemoveThisGameInstance: Bool {
        isTripCreator
            && tripGameInstanceCount >= 2
            && currentSession.status != .ended
            && currentSession.status != .cancelled
    }

    init(
        session: TripSession,
        game: GameInstance,
        tripSessionRepository: TripSessionRepositoryProtocol,
        gameInstanceRepository: GameInstanceRepositoryProtocol,
        tripActivityEventRepository: TripActivityEventRepositoryProtocol,
        lifecycleService: TripSessionLifecycleServiceProtocol,
        gameInstanceLifecycleService: GameInstanceLifecycleServiceProtocol = GameInstanceLifecycleService.shared,
        tripActivityEventRecording: TripActivityEventRecordingProtocol = TripActivityEventRecordingService.shared,
        authService: FirebaseAuthService
    ) {
        self.currentSession = session
        self.sessionId = session.id
        self.game = game
        self.tripSessionRepository = tripSessionRepository
        self.gameInstanceRepository = gameInstanceRepository
        self.tripActivityEventRepository = tripActivityEventRepository
        self.lifecycleService = lifecycleService
        self.gameInstanceLifecycleService = gameInstanceLifecycleService
        self.tripActivityEventRecording = tripActivityEventRecording
        self.authService = authService
        self.foundRegions = (try? tripActivityEventRepository.foundRegions(sessionId: session.id, gameInstanceId: game.id)) ?? []
    }

    func refreshSession() {
        if let session = try? tripSessionRepository.session(byId: sessionId) {
            currentSession = session
        }
    }

    func refreshGame() {
        if let updated = try? gameInstanceRepository.instance(byId: game.id) {
            game = updated
        }
    }

    func refreshFoundRegions() {
        foundRegions = (try? tripActivityEventRepository.foundRegions(sessionId: sessionId, gameInstanceId: game.id)) ?? []
    }

    func startTrip() throws {
        let actorId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id ?? ""
        try lifecycleService.startTrip(sessionId: sessionId, actorId: actorId)
        refreshSession()
        refreshGame()
    }

    func endTrip() throws {
        let endedBy = authService.currentUser?.firebaseUID ?? authService.currentUser?.id
        try lifecycleService.endTrip(sessionId: sessionId, endedBy: endedBy)
        refreshSession()
        refreshGame()
    }

    func startGame() throws {
        try gameInstanceLifecycleService.startGame(sessionId: sessionId, gameInstanceId: game.id)
        refreshSession()
        refreshGame()
    }

    func endGame() throws {
        try gameInstanceLifecycleService.endGame(sessionId: sessionId, gameInstanceId: game.id)
        refreshSession()
        refreshGame()
    }

    func resetGame() throws {
        try gameInstanceLifecycleService.resetGame(sessionId: sessionId, gameInstanceId: game.id)
        refreshSession()
        refreshGame()
        refreshFoundRegions()
        foundRegions = []
    }

    /// Cancels the trip session (UI: Delete trip); clears games and events via `TripSessionLifecycleService`.
    func deleteTrip() throws {
        let cancelledBy = authService.currentUser?.firebaseUID ?? authService.currentUser?.id
        try lifecycleService.cancelSession(sessionId: sessionId, cancelledBy: cancelledBy)
        refreshSession()
        refreshGame()
    }

    /// Removes this game instance from the trip (multi-game only). Pop the game screen after success.
    func deleteGameInstance() throws {
        try gameInstanceLifecycleService.deleteGame(sessionId: sessionId, gameInstanceId: game.id)
        refreshSession()
        refreshGame()
    }

    func submitDiscovery(regionID: String, inputMethod: FoundRegion.InputMethod) -> DiscoverySubmitResult {
        let participantId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id ?? ""
        let discoveries = (try? tripActivityEventRepository.discoveries(sessionId: sessionId, gameInstanceId: game.id)) ?? []
        let byTarget = Dictionary(grouping: discoveries, by: \.targetId)
        let existingDiscoveriesForTarget = byTarget[regionID] ?? []

        let result = DiscoveryRulesEngine.evaluateDiscoverySubmission(
            mode: game.commonConfig.gameMode,
            tripMode: currentSession.mode,
            existingDiscoveriesForTarget: existingDiscoveriesForTarget,
            candidateParticipantId: participantId,
            candidateTargetId: regionID,
            gameInstanceId: game.id,
            inputMethod: inputMethod,
            occurredAt: Date(),
            teams: game.teams,
            riskContext: nil
        )

        if result.outcome == .rejectedInvalidParticipant {
            rejectedDuplicateMessage = nil
            rejectedInvalidParticipantMessage = "This trip is solo, but a find is already recorded for someone else. That shouldn’t happen — someone may have access they shouldn’t.".localized
            let payload: [String: String] = [
                TripActivityEventPayloadKey.regionId: regionID,
                TripActivityEventPayloadKey.gameInstanceId: game.id.uuidString,
                TripActivityEventPayloadKey.participantId: participantId,
                TripActivityEventPayloadKey.inputMethod: inputMethod.rawValue,
                TripActivityEventPayloadKey.rejectionReason: result.outcome.rawValue,
                TripActivityEventPayloadKey.participantCount: String(currentSession.participants.count),
                TripActivityEventPayloadKey.gameMode: game.commonConfig.gameMode.rawValue
            ]
            let rejectionEvent = TripActivityEvent(
                sessionId: sessionId,
                kind: .discoveryRejected,
                actorId: participantId.isEmpty ? nil : participantId,
                payload: payload
            )
            do {
                try tripActivityEventRecording.recordForSync(rejectionEvent)
            } catch {
                AnalyticsService.shared.log(.persistenceSaveFailed(context: "trip_tracker_discovery_rejection", error: error.localizedDescription))
                return .failure(error)
            }
            AnalyticsService.shared.log(.discoveryRejectedInvalidParticipant(
                tripId: sessionId.uuidString,
                gameInstanceId: game.id.uuidString,
                targetId: regionID,
                participantId: participantId.isEmpty ? nil : participantId,
                tripParticipantCount: currentSession.participants.count,
                gameMode: game.commonConfig.gameMode.rawValue
            ))
            return .rejectedInvalidParticipant(message: rejectedInvalidParticipantMessage ?? "")
        }

        if result.outcome == .rejectedDuplicate {
            rejectedInvalidParticipantMessage = nil
            rejectedDuplicateMessage = "Only the first finder gets credit in competitive mode.".localized
            let payload: [String: String] = [
                TripActivityEventPayloadKey.regionId: regionID,
                TripActivityEventPayloadKey.gameInstanceId: game.id.uuidString,
                TripActivityEventPayloadKey.participantId: participantId,
                TripActivityEventPayloadKey.inputMethod: inputMethod.rawValue,
                TripActivityEventPayloadKey.rejectionReason: result.outcome.rawValue,
                TripActivityEventPayloadKey.participantCount: String(currentSession.participants.count),
                TripActivityEventPayloadKey.gameMode: game.commonConfig.gameMode.rawValue
            ]
            let rejectionEvent = TripActivityEvent(
                sessionId: sessionId,
                kind: .discoveryRejected,
                actorId: participantId.isEmpty ? nil : participantId,
                payload: payload
            )
            do {
                try tripActivityEventRecording.recordForSync(rejectionEvent)
            } catch {
                AnalyticsService.shared.log(.persistenceSaveFailed(context: "trip_tracker_discovery_rejection", error: error.localizedDescription))
                return .failure(error)
            }
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

        let countBeforeUniqueFound = foundRegions.count

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
            try tripActivityEventRecording.recordForSync(event)
            refreshFoundRegions()
            rejectedDuplicateMessage = nil
            rejectedInvalidParticipantMessage = nil
            AnalyticsService.shared.log(.discoveryOutcomeRecorded(
                tripId: sessionId.uuidString,
                gameInstanceId: game.id.uuidString,
                targetId: regionID,
                outcome: result.outcome.rawValue,
                participantId: participantId.isEmpty ? nil : participantId
            ))
            if game.definitionId == GameType.licensePlate.rawValue,
               let lpConfig = game.licensePlateConfig() {
                let goal = LicensePlateScopeCalculator.completionGoal(for: lpConfig)
                let countAfter = foundRegions.count
                if GameCompletionAnalyticsGate.shouldLogGameInstanceCompleted(
                    countBefore: countBeforeUniqueFound,
                    countAfter: countAfter,
                    goal: goal
                ) {
                    AnalyticsService.shared.log(.gameInstanceCompleted(
                        gameInstanceId: game.id.uuidString,
                        gameType: game.definitionId,
                        tripSessionId: sessionId.uuidString
                    ))
                }
            }
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
            try tripActivityEventRecording.recordForSync(event)
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

    func clearRejectedInvalidParticipantMessage() {
        rejectedInvalidParticipantMessage = nil
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

    /// Load countries + territory toggles for Game Settings; call when the settings sheet appears.
    func beginLicensePlateScopeDraft() {
        let defaultConfig = LicensePlateGameConfig(
            selectedCountriesRawValues: [
                PlateRegion.Country.unitedStates.rawValue,
                PlateRegion.Country.canada.rawValue,
                PlateRegion.Country.mexico.rawValue
            ],
            territoryOptions: LicensePlateTerritoryOptions()
        )
        let cfg = game.licensePlateConfig() ?? defaultConfig
        let selected = Set(cfg.selectedCountries)
        licensePlateScopeDraft = LicensePlateScopeSettingsDraft(
            includeUS: selected.contains(.unitedStates),
            includeCanada: selected.contains(.canada),
            includeMexico: selected.contains(.mexico),
            includeUSTerritories: cfg.territoryOptions.includeUSTerritories,
            includeDC: cfg.territoryOptions.includeDC,
            includeCanadianTerritories: cfg.territoryOptions.includeCanadianTerritories
        )
    }

    /// Drop draft without saving (e.g. sheet dismissed by swipe).
    func discardLicensePlateScopeDraft() {
        licensePlateScopeDraft = nil
    }

    /// Encode and persist draft to `game` (normalization applied in assembler). Clears draft on success.
    func commitLicensePlateScopeDraft() throws {
        guard let draft = licensePlateScopeDraft else { return }
        var countries: [PlateRegion.Country] = []
        if draft.includeUS { countries.append(.unitedStates) }
        if draft.includeCanada { countries.append(.canada) }
        if draft.includeMexico { countries.append(.mexico) }
        draft.applyParentGating()
        let territoryOpts = LicensePlateTerritoryOptions(
            includeUSTerritories: draft.includeUSTerritories,
            includeCanadianTerritories: draft.includeCanadianTerritories,
            includeDC: draft.includeDC
        )
        let newConfig = CombinedGameAssembler.licensePlateConfig(from: countries, territoryOptions: territoryOpts)
        let data = try JSONEncoder().encode(newConfig)
        let previousPayload = game.gameSpecificPayloadData
        game.gameSpecificPayloadData = data
        do {
            try gameInstanceRepository.update(instance: game)
            refreshGame()
            licensePlateScopeDraft = nil
            objectWillChange.send()
        } catch {
            game.gameSpecificPayloadData = previousPayload
            errorMessage = error.localizedDescription
            AnalyticsService.shared.log(.persistenceSaveFailed(context: "trip_tracker_settings", error: error.localizedDescription))
            objectWillChange.send()
            throw error
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

/// When to emit `gameInstanceCompleted` after a new find (crosses configured goal once). Tested via `@testable`.
enum GameCompletionAnalyticsGate {
    static func shouldLogGameInstanceCompleted(countBefore: Int, countAfter: Int, goal: Int) -> Bool {
        goal > 0 && countBefore < goal && countAfter >= goal
    }
}
