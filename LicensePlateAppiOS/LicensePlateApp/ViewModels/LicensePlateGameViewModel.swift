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
    @Published private(set) var foundRegions: [FoundRegion] = []
    @Published var rejectedDuplicateMessage: String?
    @Published var rejectedInvalidParticipantMessage: String?
    @Published private(set) var errorMessage: String?
    /// Editable license-plate scope while Game Settings sheet is open; persisted when user taps Done.
    @Published private(set) var licensePlateScopeDraft: LicensePlateScopeSettingsDraft?

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
            tripMode: currentSession.mode,
            existingDiscoveriesForTarget: existingDiscoveriesForTarget,
            candidateParticipantId: participantId,
            candidateTargetId: regionID,
            gameInstanceId: game.id,
            inputMethod: inputMethod,
            occurredAt: Date(),
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
                TripActivityEventPayloadKey.tripMode: currentSession.mode.rawValue,
                TripActivityEventPayloadKey.gameMode: game.commonConfig.gameMode.rawValue
            ]
            let rejectionEvent = TripActivityEvent(
                sessionId: sessionId,
                kind: .discoveryRejected,
                actorId: participantId.isEmpty ? nil : participantId,
                payload: payload
            )
            do {
                try tripActivityEventRepository.append(rejectionEvent)
                try? syncCoordinator.enqueueForSync(sessionId: sessionId, eventId: rejectionEvent.id)
            } catch {
                AnalyticsService.shared.log(.persistenceSaveFailed(context: "trip_tracker_discovery_rejection", error: error.localizedDescription))
                return .failure(error)
            }
            AnalyticsService.shared.log(.discoveryRejectedInvalidParticipant(
                tripId: sessionId.uuidString,
                gameInstanceId: game.id.uuidString,
                targetId: regionID,
                participantId: participantId.isEmpty ? nil : participantId,
                tripMode: currentSession.mode.rawValue,
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
                TripActivityEventPayloadKey.tripMode: currentSession.mode.rawValue,
                TripActivityEventPayloadKey.gameMode: game.commonConfig.gameMode.rawValue
            ]
            let rejectionEvent = TripActivityEvent(
                sessionId: sessionId,
                kind: .discoveryRejected,
                actorId: participantId.isEmpty ? nil : participantId,
                payload: payload
            )
            do {
                try tripActivityEventRepository.append(rejectionEvent)
                try? syncCoordinator.enqueueForSync(sessionId: sessionId, eventId: rejectionEvent.id)
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
            rejectedInvalidParticipantMessage = nil
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
