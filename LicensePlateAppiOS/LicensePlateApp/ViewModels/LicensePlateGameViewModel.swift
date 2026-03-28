//
//  LicensePlateGameViewModel.swift
//  LicensePlateApp
//
//  Step 6.8 — ViewModel for license plate game screen (game-level only).
//

import Foundation
import Combine

/// Server fairness messaging after sync (Step 13); stacked non-blocking banners in-game.
struct FairnessToastState: Equatable, Identifiable {
    let id: UUID
    var title: String
    var message: String

    init(title: String, message: String) {
        self.id = UUID()
        self.title = title
        self.message = message
    }
}

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
    /// Competitive mode: ranked standings for this game instance (roster merged).
    @Published private(set) var competitiveStandings: [RankedParticipantContribution] = []
    /// Competitive: current user’s `discoveryRejected` duplicate attempts for this game.
    @Published private(set) var myDuplicateRejections: [CompetitiveDuplicateAttempt] = []
    @Published var rejectedDuplicateMessage: String?
    @Published var rejectedInvalidParticipantMessage: String?
    @Published private(set) var errorMessage: String?
    /// Editable license-plate scope while Game Settings sheet is open; persisted when user taps Done.
    @Published private(set) var licensePlateScopeDraft: LicensePlateScopeSettingsDraft?
    /// Step 13 — server rejected a late competitive find; stacked banners (newest first) in `LicensePlateGameView`.
    @Published private(set) var fairnessToasts: [FairnessToastState] = []

    let sessionId: UUID

    private let tripSessionRepository: TripSessionRepositoryProtocol
    private let gameInstanceRepository: GameInstanceRepositoryProtocol
    private let tripActivityEventRepository: TripActivityEventRepositoryProtocol
    private let lifecycleService: TripSessionLifecycleServiceProtocol
    private let gameInstanceLifecycleService: GameInstanceLifecycleServiceProtocol
    private let tripActivityEventRecording: TripActivityEventRecordingProtocol
    private let authService: FirebaseAuthService
    private var didLogCompetitiveStandingsExposure = false
    private var cancellables = Set<AnyCancellable>()
    /// Dedupes fairness alert when the same `discovery_rejected` arrives via sync and Firestore listener.
    private var shownFairnessRejectionEventIds = Set<String>()

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
        refreshCompetitiveProjections()

        TripCanonicalRemoteSyncService.shared.fairnessResolutionSignal
            .filter { [weak self] info in
                guard let self else { return false }
                return info.tripSessionId == self.sessionId && info.gameInstanceId == self.game.id
            }
            .receive(on: RunLoop.main)
            .sink { [weak self] info in
                guard let self else { return }
                Task { await self.appendFairnessToastForResolution(info) }
            }
            .store(in: &cancellables)

        // `ContentView` only reloads the active-trip list on hydration; game UI must refresh too.
        TripCanonicalRemoteSyncService.shared.hydrationSignal
            .filter { [weak self] hydratedId in
                guard let self else { return false }
                return hydratedId == self.sessionId
            }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.refreshSession()
                self.refreshGame()
                self.refreshFoundRegions()
                self.presentFairnessToastIfNewRemoteRejection()
            }
            .store(in: &cancellables)

        if currentSession.mode == .multiplayer {
            TripCanonicalRemoteSyncService.shared.startIncrementalListeningIfNeeded(sessionId: sessionId)
        }
    }

    func clearFairnessToast(id: UUID) {
        fairnessToasts.removeAll { $0.id == id }
    }

    /// Callable supersede path and per-rejection hydration: append one banner; dedupes by `sourceRejectionEventId`.
    private func appendFairnessToastForResolution(_ info: FairnessResolutionInfo, refreshAfter: Bool = true) async {
        if let id = info.sourceRejectionEventId {
            guard !shownFairnessRejectionEventIds.contains(id) else { return }
            shownFairnessRejectionEventIds.insert(id)
        }
        let regionName = PlateRegion.all.first(where: { $0.id == info.regionId })?.name ?? info.regionId
        let names = await UserRepository.shared.displayNames(forUserIds: [info.firstFinderParticipantId])
        let firstName = names[info.firstFinderParticipantId] ?? info.firstFinderParticipantId
        let tripName = info.tripSessionName
        let message: String
        if info.rejectionReasonRaw == DiscoveryOutcome.serverRejectedLateCompetitive.rawValue {
            message = "Fairness late competitive body %@ %@ %@".localized(regionName, firstName, tripName)
        } else {
            message = "Fairness invalid participant body %@ %@".localized(regionName, tripName)
        }
        fairnessToasts.append(FairnessToastState(title: "Region selection order resolution".localized, message: message))
        if refreshAfter {
            refreshFoundRegions()
            refreshCompetitiveProjections()
        }
    }

    /// Firestore can merge a peer’s winning find + server `discovery_rejected` before local sync returns; stacked banners for each not-yet-shown fairness rejection (newest first).
    private func presentFairnessToastIfNewRemoteRejection() {
        guard game.commonConfig.gameMode == .competitive else { return }
        let uid = authService.currentUser?.firebaseUID ?? authService.currentUser?.id ?? ""
        guard !uid.isEmpty else { return }
        guard let allEvents = try? tripActivityEventRepository.events(sessionId: sessionId, limit: nil) else { return }
        let gid = game.id.uuidString
        let tripName = currentSession.name
        let candidates = allEvents.filter { event in
            guard event.kind == .discoveryRejected, let p = event.payload else { return false }
            guard p[TripActivityEventPayloadKey.gameInstanceId] == gid else { return false }
            let attempter = p[TripActivityEventPayloadKey.participantId] ?? event.actorId ?? ""
            guard attempter == uid else { return false }
            guard !shownFairnessRejectionEventIds.contains(event.id) else { return false }
            return FairnessResolutionInfo(rejection: event, sessionId: sessionId, tripSessionName: tripName) != nil
        }
        let ordered = candidates.sorted { $0.timestamp > $1.timestamp }
        let infos: [FairnessResolutionInfo] = ordered.compactMap {
            FairnessResolutionInfo(rejection: $0, sessionId: sessionId, tripSessionName: tripName)
        }
        guard !infos.isEmpty else { return }
        Task {
            for info in infos {
                await appendFairnessToastForResolution(info, refreshAfter: false)
            }
            refreshFoundRegions()
            refreshCompetitiveProjections()
        }
    }

    func refreshSession() {
        if let session = try? tripSessionRepository.session(byId: sessionId) {
            currentSession = session
        }
        refreshCompetitiveProjections()
    }

    func refreshGame() {
        if let updated = try? gameInstanceRepository.instance(byId: game.id) {
            game = updated
        }
        refreshCompetitiveProjections()
    }

    func refreshFoundRegions() {
        foundRegions = (try? tripActivityEventRepository.foundRegions(sessionId: sessionId, gameInstanceId: game.id)) ?? []
        refreshCompetitiveProjections()
    }

    /// Rebuilds competitive standings and duplicate-rejection history from the event log.
    func refreshCompetitiveProjections() {
        guard game.commonConfig.gameMode == .competitive else {
            competitiveStandings = []
            myDuplicateRejections = []
            return
        }

        let uid = authService.currentUser?.firebaseUID ?? authService.currentUser?.id ?? ""

        guard let discoveries = try? tripActivityEventRepository.discoveries(sessionId: sessionId, gameInstanceId: game.id) else {
            competitiveStandings = []
            myDuplicateRejections = []
            return
        }

        let byTarget = Dictionary(grouping: discoveries, by: \.targetId)
        let credits = DiscoveryRulesEngine.creditsForDiscoveries(
            mode: game.commonConfig.gameMode,
            discoveriesByTarget: byTarget,
            teams: game.teams
        )
        let raw = ParticipantContributionBuilder.contributionSummary(discoveries: discoveries, credits: credits)
        let merged = TripRosterContributionMerge.merge(roster: currentSession.participants, contributions: raw)
        competitiveStandings = TripParticipantRanking.rankContributions(merged)

        if let allEvents = try? tripActivityEventRepository.events(sessionId: sessionId, limit: nil) {
            let gidStr = game.id.uuidString
            let rejected = allEvents
                .filter { $0.kind == .discoveryRejected }
                .filter { $0.payload?[TripActivityEventPayloadKey.gameInstanceId] == gidStr }
                .filter { $0.payload?[TripActivityEventPayloadKey.rejectionReason] == DiscoveryOutcome.rejectedDuplicate.rawValue }
                .filter { event in
                    let pid = event.payload?[TripActivityEventPayloadKey.participantId] ?? event.actorId ?? ""
                    return !uid.isEmpty && pid == uid
                }
                .sorted { $0.timestamp > $1.timestamp }
            myDuplicateRejections = rejected.map {
                CompetitiveDuplicateAttempt(
                    id: $0.id,
                    targetId: $0.payload?[TripActivityEventPayloadKey.regionId] ?? "",
                    timestamp: $0.timestamp
                )
            }
        } else {
            myDuplicateRejections = []
        }

        if currentSession.mode == .multiplayer, !didLogCompetitiveStandingsExposure {
            AnalyticsService.shared.log(.competitiveInGameStandingsPresented(
                tripSessionId: sessionId.uuidString,
                gameInstanceId: game.id.uuidString
            ))
            didLogCompetitiveStandingsExposure = true
        }
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
            refreshCompetitiveProjections()
            return .rejectedDuplicate(message: rejectedDuplicateMessage ?? "")
        }

        guard result.shouldAppendEvent else {
            return .success
        }

        let countBeforeUniqueFound = foundRegions.count

        let discoveryEventId = UUID().uuidString
        var payload: [String: String] = [
            TripActivityEventPayloadKey.regionId: regionID,
            TripActivityEventPayloadKey.gameInstanceId: game.id.uuidString,
            TripActivityEventPayloadKey.participantId: participantId,
            TripActivityEventPayloadKey.inputMethod: inputMethod.rawValue,
            TripActivityEventPayloadKey.discoveryEventId: discoveryEventId
        ]
        let event = TripActivityEvent(
            id: discoveryEventId,
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
        refreshSession()
        let participantId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id ?? ""
        guard !participantId.isEmpty else {
            errorMessage = "Sign in to remove a find.".localized
            objectWillChange.send()
            return
        }

        let discoveries = (try? tripActivityEventRepository.discoveries(sessionId: sessionId, gameInstanceId: game.id)) ?? []
        let forTarget = discoveries.filter { $0.targetId == regionID }
        let mine = forTarget.filter { $0.participantId == participantId }
        guard let toRemove = mine.max(by: { $0.discoveredAt < $1.discoveredAt }) else {
            errorMessage = "You don’t have a find to remove for this region.".localized
            objectWillChange.send()
            return
        }

        guard GameModeRulesEngine.canParticipantUnfind(
            mode: game.commonConfig.gameMode,
            participantId: participantId,
            discovery: toRemove,
            allDiscoveriesForTarget: forTarget
        ) else {
            errorMessage = "You can’t remove this find.".localized
            objectWillChange.send()
            return
        }

        var payload: [String: String] = [
            TripActivityEventPayloadKey.regionId: regionID,
            TripActivityEventPayloadKey.gameInstanceId: game.id.uuidString,
            TripActivityEventPayloadKey.removedDiscoveryEventId: toRemove.id
        ]
        let event = TripActivityEvent(sessionId: sessionId, kind: .regionRemoved, payload: payload)
        do {
            try tripActivityEventRecording.recordForSync(event)
            AnalyticsService.shared.log(.discoveryUnfind(
                tripId: sessionId.uuidString,
                gameInstanceId: game.id.uuidString,
                targetId: regionID,
                participantId: participantId
            ))
            errorMessage = nil
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
