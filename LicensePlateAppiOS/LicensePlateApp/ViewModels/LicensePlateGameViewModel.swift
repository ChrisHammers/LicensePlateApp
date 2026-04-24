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
    /// `TripActivityEvent.id` for `discovery_rejected` when present; used for tap-to-ack watermark.
    let sourceRejectionEventId: String?
    var title: String
    var message: String

    init(sourceRejectionEventId: String?, title: String, message: String) {
        self.id = UUID()
        self.sourceRejectionEventId = sourceRejectionEventId
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
    @Published var blockedRetapMessage: String?
    @Published private(set) var errorMessage: String?
    /// Editable license-plate scope while Game Settings sheet is open; persisted when user taps Done.
    @Published private(set) var licensePlateScopeDraft: LicensePlateScopeSettingsDraft?
    /// Step 13 — server rejected a late competitive find; stacked banners (oldest at top) in `LicensePlateGameView`.
    @Published private(set) var fairnessToasts: [FairnessToastState] = []
    /// Ledger-driven per-region read models for the current viewer (Step XP 03).
    @Published private(set) var discoveryProjectionsByItemId: [String: DiscoveryUiProjection] = [:]
    /// Pre-built row copy/accessibility for list/map (derived from `discoveryProjectionsByItemId`).
    @Published private(set) var plateRowPresentationsByRegionId: [String: RegionPlateRowPresentation] = [:]
    /// All game modes: ranked per-participant scoring (weighted score, first finds) for this game (Progress tab).
    @Published private(set) var rankedScoringForCurrentGame: [RankedParticipantContribution] = []
    /// `ProgressionLocalEngine` pending for this trip session: events not yet in server `appliedProgressionEvents` (read-only local projection).
    @Published private(set) var sessionProgressionPending: ProgressionPendingDelta = .zero
    /// This session’s append-only XP ledger for the current user (Progress tab list).
    @Published private(set) var sessionLedgerEvents: [XpLedgerEvent] = []
    /// Ledger-only local XP for this user + **this game** (`XpBalanceProjectionBuilder`); net includes all row statuses, with provisional called out.
    @Published private(set) var localGameLedgerBalance: XpBalanceProjection?
    /// Sum of `provisional` rows on this device for **this session** (all games); pairs with `sessionLedgerEvents`.
    @Published private(set) var localSessionLedgerPending: LedgerPendingXpTotals = LedgerPendingXpTotals.fromLedgerEvents([])
    /// All sessions on device: sum of ledger `provisional` rows (same basis as `XpProgressViewModel` / profile rank overlay).
    @Published private(set) var accountLedgerProvisionalPending: Int = 0

    let sessionId: UUID

    private let tripSessionRepository: TripSessionRepositoryProtocol
    private let gameInstanceRepository: GameInstanceRepositoryProtocol
    private let tripActivityEventRepository: TripActivityEventRepositoryProtocol
    private let xpLedger: XpLedgerRepositoryProtocol
    private let discoveryResolutionRepository: DiscoveryResolutionRepositoryProtocol
    private let lifecycleService: TripSessionLifecycleServiceProtocol
    private let gameInstanceLifecycleService: GameInstanceLifecycleServiceProtocol
    private let tripActivityEventRecording: TripActivityEventRecordingProtocol
    private let regionRemovalCooldownService: RegionRemovalCooldownServiceProtocol
    private let authService: FirebaseAuthService
    private var didLogCompetitiveStandingsExposure = false
    private var cancellables = Set<AnyCancellable>()
    /// Dedupes fairness alert when the same `discovery_rejected` arrives via sync and Firestore listener.
    private var shownFairnessRejectionEventIds = Set<String>()
    /// Prevents interleaved `applyFairnessToastBacklogFromEventLog(` init `Task` vs tests / hydration) from splitting backlog work and advancing the watermark to only the first rejection.) and runs from duplicating toast rows.
    private var isApplyingFairnessToastBacklog = false
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

    /// Count of regions shown as found in the scoped board (projection-first when available).
    var displayFoundCountForHeader: Int {
        if !plateRowPresentationsByRegionId.isEmpty {
            return plateRowPresentationsByRegionId.values.filter(\.isVisuallyFound).count
        }
        return foundRegions.count
    }

    /// Region ids shown as found on map/list (projection-first when available).
    var displayFoundRegionIDsForMap: [String] {
        if !plateRowPresentationsByRegionId.isEmpty {
            return plateRowPresentationsByRegionId.filter { $0.value.isVisuallyFound }.map(\.key)
        }
        return foundRegions.map(\.regionID)
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
        regionRemovalCooldownService: RegionRemovalCooldownServiceProtocol = RegionRemovalCooldownService(),
        authService: FirebaseAuthService,
        xpLedger: XpLedgerRepositoryProtocol = XpLedgerRepository.shared,
        discoveryResolutionRepository: DiscoveryResolutionRepositoryProtocol = DiscoveryResolutionRepository.shared
    ) {
        self.currentSession = session
        self.sessionId = session.id
        self.game = game
        self.tripSessionRepository = tripSessionRepository
        self.gameInstanceRepository = gameInstanceRepository
        self.tripActivityEventRepository = tripActivityEventRepository
        self.xpLedger = xpLedger
        self.discoveryResolutionRepository = discoveryResolutionRepository
        self.lifecycleService = lifecycleService
        self.gameInstanceLifecycleService = gameInstanceLifecycleService
        self.tripActivityEventRecording = tripActivityEventRecording
        self.regionRemovalCooldownService = regionRemovalCooldownService
        self.authService = authService
        self.foundRegions = (try? tripActivityEventRepository.foundRegions(sessionId: session.id, gameInstanceId: game.id)) ?? []
        refreshCompetitiveProjections()

        let selfUid = authService.currentUser?.firebaseUID ?? authService.currentUser?.id
        UserProfileListenCoordinator.shared.setPinnedUsers(
            selfUserId: selfUid,
            rosterUserIds: Self.rosterUserIds(for: session)
        )

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
                Task {
                    await self.mergeFairnessUiAckFromRemoteIfNeeded()
                    await self.applyFairnessToastBacklogFromEventLog()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .userProfilesMerged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshPlateProjections()
            }
            .store(in: &cancellables)

        if currentSession.mode == .multiplayer {
            TripCanonicalRemoteSyncService.shared.startIncrementalListeningIfNeeded(sessionId: sessionId)
        }

        Task {
            await mergeFairnessUiAckFromRemoteIfNeeded()
            await applyFairnessToastBacklogFromEventLog()
        }
    }

    func clearFairnessToast(id: UUID) {
        guard let toast = fairnessToasts.first(where: { $0.id == id }) else { return }
        fairnessToasts.removeAll { $0.id == id }
        guard let sourceRejectionEventId = toast.sourceRejectionEventId else { return }
        shownFairnessRejectionEventIds.insert(sourceRejectionEventId)
        Task { await advanceFairnessWatermark(forRejectionEventIds: [sourceRejectionEventId]) }
    }

    /// Clears in-game fairness banners and session dedupe after trip end/cancel or game reset.
    private func clearFairnessToastUIState() {
        fairnessToasts = []
        shownFairnessRejectionEventIds.removeAll()
    }

    /// Re-merge fairness watermark and scan `discovery_rejected` backlog when returning to the game or after sync (no app restart).
    func refreshFairnessUiAfterNavigationOrReconnect() async {
        await mergeFairnessUiAckFromRemoteIfNeeded()
        await applyFairnessToastBacklogFromEventLog()
    }

    /// Merges Firebase `fairness_ack_watermarks` into SwiftData (multiplayer competitive only).
    private func mergeFairnessUiAckFromRemoteIfNeeded() async {
        guard currentSession.mode == .multiplayer else { return }
        guard game.commonConfig.gameMode == .competitive else { return }
        let uid = authService.currentUser?.firebaseUID ?? authService.currentUser?.id ?? ""
        guard !uid.isEmpty else { return }
        let remote = try? await FairnessAckWatermarkRemoteService.shared.fetchWatermark(
            tripSessionId: sessionId,
            gameInstanceId: game.id,
            userId: uid
        )
        let local = game.fairnessUiLastAckAt
        let merged = [local, remote].compactMap { $0 }.max()
        guard let m = merged else { return }

        let localDiffers = game.fairnessUiLastAckAt.map { $0 != m } ?? true
        if localDiffers {
            game.fairnessUiLastAckAt = m
            try? gameInstanceRepository.update(instance: game)
            objectWillChange.send()
        }

        let shouldPush: Bool
        if let r = remote {
            shouldPush = m > r
        } else {
            shouldPush = true
        }
        if shouldPush {
            do {
                try await FairnessAckWatermarkRemoteService.shared.pushWatermark(
                    tripSessionId: sessionId,
                    gameInstanceId: game.id,
                    lastAckAt: m
                )
            } catch {
                #if DEBUG
                print("LicensePlateGameViewModel: push fairness watermark failed \(error)")
                #endif
            }
        }
    }

    private func advanceFairnessWatermark(forRejectionEventIds ids: [String]) async {
        guard game.commonConfig.gameMode == .competitive else { return }
        guard !ids.isEmpty else { return }
        let dates = ids.compactMap { id -> Date? in
            guard let ev = try? tripActivityEventRepository.event(byId: id) else { return nil }
            return ev.timestamp
        }
        guard let maxTs = dates.max() else { return }
        let prior = game.fairnessUiLastAckAt ?? .distantPast
        guard maxTs > prior else { return }
        game.fairnessUiLastAckAt = maxTs
        do {
            try gameInstanceRepository.update(instance: game)
        } catch {
            #if DEBUG
            print("LicensePlateGameViewModel: persist fairness watermark failed \(error)")
            #endif
            return
        }
        guard currentSession.mode == .multiplayer else { return }
        let uid = authService.currentUser?.firebaseUID ?? authService.currentUser?.id ?? ""
        guard !uid.isEmpty else { return }
        do {
            try await FairnessAckWatermarkRemoteService.shared.pushWatermark(
                tripSessionId: sessionId,
                gameInstanceId: game.id,
                lastAckAt: maxTs
            )
        } catch {
            #if DEBUG
            print("LicensePlateGameViewModel: push fairness watermark after ack failed \(error)")
            #endif
        }
    }

    /// Returns `true` if a new toast row was appended.
    private func appendFairnessToastContentIfNew(_ info: FairnessResolutionInfo) async -> Bool {
        if let id = info.sourceRejectionEventId {
            guard !shownFairnessRejectionEventIds.contains(id) else { return false }
            if let ev = try? tripActivityEventRepository.event(byId: id),
               let c = game.fairnessUiLastAckAt,
               !(ev.timestamp > c) {
                shownFairnessRejectionEventIds.insert(id)
                return false
            }
            shownFairnessRejectionEventIds.insert(id)
        }
        let regionName = PlateRegion.all.first(where: { $0.id == info.regionId })?.name ?? info.regionId
        let names = await UserRepository.shared.displayNames(forUserIds: [info.firstFinderParticipantId])
        let firstName = names[info.firstFinderParticipantId] ?? info.firstFinderParticipantId
        let tripName = info.tripSessionName
        let message: String
        if info.rejectionReasonRaw == DiscoveryRejectionReason.serverRejectedLateCompetitive.rawValue
            || info.rejectionReasonRaw == DiscoveryRejectionReason.serverRejectedSupersededByEarlierTimestamp.rawValue {
            message = "Fairness late competitive body %@ %@ %@".localized(regionName, firstName, tripName)
        } else {
            message = "Fairness invalid participant body %@ %@".localized(regionName, tripName)
        }
        fairnessToasts.append(FairnessToastState(
            sourceRejectionEventId: info.sourceRejectionEventId,
            title: "Region selection order resolution".localized,
            message: message
        ))
        return true
    }

    /// Callable supersede path and per-rejection hydration: append one banner; dedupes by `sourceRejectionEventId`.
    private func appendFairnessToastForResolution(_ info: FairnessResolutionInfo, refreshAfter: Bool = true) async {
        let appended = await appendFairnessToastContentIfNew(info)
        guard appended else { return }
        if refreshAfter {
            refreshFoundRegions()
            refreshCompetitiveProjections()
        }
    }

    /// Firestore can merge a peer’s winning find + server `discovery_rejected` before local sync returns; stacked banners oldest-first.
    internal func applyFairnessToastBacklogFromEventLog() async {
        guard !isApplyingFairnessToastBacklog else { return }
        isApplyingFairnessToastBacklog = true
        defer { isApplyingFairnessToastBacklog = false }
        guard game.commonConfig.gameMode == .competitive else { return }
        let uid = authService.currentUser?.firebaseUID ?? authService.currentUser?.id ?? ""
        guard !uid.isEmpty else { return }
        guard let allEvents = try? tripActivityEventRepository.events(sessionId: sessionId, limit: nil) else { return }
        let gid = game.id.uuidString
        let tripName = currentSession.name
        let cutoff = game.fairnessUiLastAckAt
        let candidates = allEvents.filter { event in
            guard event.kind == .discoveryRejected, let p = event.payload else { return false }
            guard p[TripActivityEventPayloadKey.gameInstanceId] == gid else { return false }
            let attempter = p[TripActivityEventPayloadKey.participantId] ?? event.actorId ?? ""
            guard attempter == uid else { return false }
            if let c = cutoff, !(event.timestamp > c) { return false }
            guard !shownFairnessRejectionEventIds.contains(event.id) else { return false }
            return FairnessResolutionInfo(rejection: event, sessionId: sessionId, tripSessionName: tripName) != nil
        }
        let ordered = candidates.sorted { $0.timestamp < $1.timestamp }
        let infos: [FairnessResolutionInfo] = ordered.compactMap {
            FairnessResolutionInfo(rejection: $0, sessionId: sessionId, tripSessionName: tripName)
        }
        guard !infos.isEmpty else { return }
        for info in infos {
            _ = await appendFairnessToastContentIfNew(info)
        }
        refreshFoundRegions()
        refreshCompetitiveProjections()
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

    /// Rebuilds competitive standings and duplicate-rejection history from the event log; also `rankedScoringForCurrentGame` for all modes.
    func refreshCompetitiveProjections() {
        defer { refreshPlateProjections() }

        guard game.commonConfig.gameMode == .competitive else {
            competitiveStandings = []
            myDuplicateRejections = []
            return
        }

        let uid = authService.currentUser?.firebaseUID ?? authService.currentUser?.id ?? ""

        guard let discoveries = try? tripActivityEventRepository.discoveries(sessionId: sessionId, gameInstanceId: game.id) else {
            competitiveStandings = []
            myDuplicateRejections = []
            rankedScoringForCurrentGame = []
            refreshProgressionDebugState()
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
        let ranked = TripParticipantRanking.rankContributions(merged)
        rankedScoringForCurrentGame = ranked

        if game.commonConfig.gameMode == .competitive {
            competitiveStandings = ranked

            if let allEvents = try? tripActivityEventRepository.events(sessionId: sessionId, limit: nil) {
                let gidStr = game.id.uuidString
                let rejected = allEvents
                    .filter { $0.kind == .discoveryRejected }
                    .filter { $0.payload?[TripActivityEventPayloadKey.gameInstanceId] == gidStr }
                    .filter { $0.payload?[TripActivityEventPayloadKey.rejectionReason] == DiscoveryRejectionReason.rejectedDuplicate.rawValue }
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
        
        refreshProgressionDebugState()
    }

    /// Recomputes local `ProgressionLocalEngine` session pending and the XP ledger for the Progress tab.
    func refreshProgressionDebugState() {
        let uid = authService.currentUser?.firebaseUID ?? authService.currentUser?.id ?? ""
        guard !uid.isEmpty else {
            sessionProgressionPending = .zero
            sessionLedgerEvents = []
            localGameLedgerBalance = nil
            localSessionLedgerPending = LedgerPendingXpTotals.fromLedgerEvents([])
            accountLedgerProvisionalPending = 0
            return
        }

        let events = (try? tripActivityEventRepository.events(sessionId: sessionId, limit: nil)) ?? []
        let roster = currentSession.participants.filter { $0.leftAt == nil }.map(\.userId)
        var gamesById: [UUID: ProgressionGameSnapshot] = [:]
        if let games = try? gameInstanceRepository.fetchByTripSession(sessionId: sessionId) {
            gamesById = Dictionary(uniqueKeysWithValues: games.map { ($0.id, $0.progressionGameSnapshot) })
        } else {
            gamesById = [game.id: game.progressionGameSnapshot]
        }
        let server = UserProgressionRepository.shared.snapshot ?? UserProgressionSnapshot.empty
        sessionProgressionPending = ProgressionLocalEngine.pendingDeltaForSession(
            sortedSessionEvents: events,
            rosterUserIds: roster,
            subjectUserId: uid,
            serverAppliedEventIds: server.appliedProgressionEventIds,
            gamesById: gamesById
        )
        let rows = (try? xpLedger.ledgerEvents(userId: uid, sessionId: sessionId)) ?? []
        let now = Date()
        sessionLedgerEvents = rows
        localSessionLedgerPending = LedgerPendingXpTotals.fromLedgerEvents(rows, now: now)
        localGameLedgerBalance = XpBalanceProjectionBuilder.build(
            userId: uid,
            sessionId: sessionId,
            gameInstanceId: game.id,
            ledgerEvents: rows,
            now: now
        )
        let allUserLedger = (try? xpLedger.ledgerEvents(userId: uid)) ?? []
        accountLedgerProvisionalPending = LedgerPendingXpTotals.fromLedgerEvents(allUserLedger, now: now).provisionalSum
    }

    private func defaultLicensePlateGameConfig() -> LicensePlateGameConfig {
        LicensePlateGameConfig(
            selectedCountriesRawValues: [
                PlateRegion.Country.unitedStates.rawValue,
                PlateRegion.Country.canada.rawValue,
                PlateRegion.Country.mexico.rawValue
            ],
            territoryOptions: LicensePlateTerritoryOptions()
        )
    }

    private static func rosterUserIds(for session: TripSession) -> Set<String> {
        var ids = Set(session.participants.map(\.userId).filter { !$0.isEmpty })
        if let createdBy = session.createdBy, !createdBy.isEmpty {
            ids.insert(createdBy)
        }
        return ids
    }

    /// Rebuilds `discoveryProjectionsByItemId` and row presentations from activity replay + ledger + resolutions.
    private func refreshPlateProjections() {
        let uid = authService.currentUser?.firebaseUID ?? authService.currentUser?.id ?? ""
        guard !uid.isEmpty else {
            discoveryProjectionsByItemId = [:]
            plateRowPresentationsByRegionId = [:]
            return
        }

        guard game.definitionId == GameType.licensePlate.rawValue else {
            discoveryProjectionsByItemId = [:]
            plateRowPresentationsByRegionId = [:]
            return
        }

        let lpConfig = game.licensePlateConfig() ?? defaultLicensePlateGameConfig()
        let targetIds = LicensePlateScopeCalculator.targetRegionIds(for: lpConfig)
        let discoveries = (try? tripActivityEventRepository.discoveries(sessionId: sessionId, gameInstanceId: game.id)) ?? []
        let byTarget = Dictionary(grouping: discoveries, by: \.targetId)
        let allFinderIds = Set(discoveries.map(\.participantId).filter { !$0.isEmpty })
        let cachedIdentities = UserRepository.shared.cachedIdentityMap(forUserIds: allFinderIds)

        var projections: [String: DiscoveryUiProjection] = [:]
        var rows: [String: RegionPlateRowPresentation] = [:]

        for regionId in targetIds {
            let forItem = byTarget[regionId] ?? []
            let ledgerRows = (try? xpLedger.ledgerEvents(
                userId: uid,
                sessionId: sessionId,
                gameInstanceId: game.id,
                itemId: regionId,
                statuses: nil
            )) ?? []
            let resolutionList = (try? discoveryResolutionRepository.resolutions(
                sessionId: sessionId,
                gameInstanceId: game.id,
                itemId: regionId
            )) ?? []
            let resolution = DiscoveryResolution.preferredLatest(in: resolutionList)

            let projection = DiscoveryUiProjectionBuilder.project(
                sessionId: sessionId,
                gameInstanceId: game.id,
                itemId: regionId,
                viewerUserId: uid,
                gameMode: game.commonConfig.gameMode,
                discoveriesForItem: forItem,
                resolution: resolution,
                ledgerEventsForItem: ledgerRows,
                lastUpdated: Date()
            )
            projections[regionId] = projection

            let regionName = PlateRegion.all.first { $0.id == regionId }?.name ?? regionId
            let foundFallback = foundRegions.contains { $0.regionID == regionId }
            let orderedFinders = finderPresentations(for: forItem, identities: cachedIdentities)
            let findersA11y = findersAccessibilityValue(orderedFinders: orderedFinders)
            rows[regionId] = RegionPlateRowPresentationBuilder.build(
                regionId: regionId,
                regionName: regionName,
                projection: projection,
                foundFallback: foundFallback,
                orderedFinders: orderedFinders,
                findersAccessibilityValue: findersA11y
            )
        }

        discoveryProjectionsByItemId = projections
        plateRowPresentationsByRegionId = rows
    }

    private func finderPresentations(
        for discoveries: [GameDiscovery],
        identities: [String: UserRepository.UserIdentitySnapshot]
    ) -> [FinderAvatarPresentation] {
        var seen = Set<String>()
        let ordered = discoveries
            .sorted(by: GameDiscovery.orderingAscending)
            .compactMap { discovery -> FinderAvatarPresentation? in
                let id = discovery.participantId
                guard !id.isEmpty, !seen.contains(id) else { return nil }
                seen.insert(id)
                let identity = identities[id]
                return FinderAvatarPresentation(
                    participantId: id,
                    displayName: identity?.displayName ?? id,
                    avatarId: identity?.avatarId,
                    legacyFallbackImageName: identity?.legacyFallbackImageName,
                    foundAt: discovery.discoveredAt
                )
            }
        return ordered
    }

    private func findersAccessibilityValue(orderedFinders: [FinderAvatarPresentation]) -> String? {
        guard !orderedFinders.isEmpty else { return nil }
        let names = orderedFinders.map(\.displayName)
        if names.count == 1 {
            return "finder.a11y.single".localized(names[0])
        }
        let joined = names.joined(separator: ", ")
        return "finder.a11y.ordered_list".localized(joined)
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
        clearFairnessToastUIState()
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
        clearFairnessToastUIState()
    }

    /// Cancels the trip session (UI: Delete trip); clears games and events via `TripSessionLifecycleService`.
    func deleteTrip() throws {
        let cancelledBy = authService.currentUser?.firebaseUID ?? authService.currentUser?.id
        try lifecycleService.cancelSession(sessionId: sessionId, cancelledBy: cancelledBy)
        refreshSession()
        refreshGame()
        clearFairnessToastUIState()
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

    func canSubmitDiscoveryTap(regionID: String) -> Bool {
        /// Not currently wanting to make you have to tap something else. Good boilerplate for later though.
        if regionRemovalCooldownService.shouldBlockTap(regionId: regionID) {
            // Inline toast/banner for this case is disabled in `LicensePlateGameView`; cooldown + removal alert remain.
            // blockedRetapMessage = "Pick a different region before selecting this one again.".localized
            // AnalyticsService.shared.log(.discoveryRetapBlockedByCooldown(
            //     tripId: sessionId.uuidString,
            //     gameInstanceId: game.id.uuidString,
            //     targetId: regionID
            // ))
            // return false
        }
        blockedRetapMessage = nil
        return true
    }
    
    @discardableResult
    func removeDiscoveryButtonPressed(regionID: String) -> Bool {
        let participantId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id ?? ""
        regionRemovalCooldownService.registerConfirmedRemoval(regionId: regionID)
        AnalyticsService.shared.log(.discoveryRemovalConfirmed(
            tripId: sessionId.uuidString,
            gameInstanceId: game.id.uuidString,
            targetId: regionID,
            participantId: participantId
        ))
        return removeDiscovery(regionID: regionID)
    }
    
    func removeDiscovery(regionID: String) -> Bool {
        refreshSession()
        let participantId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id ?? ""
        guard !participantId.isEmpty else {
            errorMessage = "Sign in to remove a find.".localized
            objectWillChange.send()
            return false
        }

        let discoveries = (try? tripActivityEventRepository.discoveries(sessionId: sessionId, gameInstanceId: game.id)) ?? []
        let forTarget = discoveries.filter { $0.targetId == regionID }
        let mine = forTarget.filter { $0.participantId == participantId }
        guard let toRemove = mine.max(by: { $0.discoveredAt < $1.discoveredAt }) else {
            errorMessage = "You don’t have a find to remove for this region.".localized
            objectWillChange.send()
            return false
        }

        guard GameModeRulesEngine.canParticipantUnfind(
            mode: game.commonConfig.gameMode,
            participantId: participantId,
            discovery: toRemove,
            allDiscoveriesForTarget: forTarget
        ) else {
            errorMessage = "You can’t remove this find.".localized
            objectWillChange.send()
            return false
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
            AnalyticsService.shared.log(.discoveryUnfind(
                tripId: sessionId.uuidString,
                gameInstanceId: game.id.uuidString,
                targetId: regionID,
                participantId: participantId
            ))
            errorMessage = nil
            refreshFoundRegions()
            return true
        } catch {
            errorMessage = error.localizedDescription
            AnalyticsService.shared.log(.persistenceSaveFailed(context: "trip_tracker_unfind", error: error.localizedDescription))
            objectWillChange.send()
            return false
        }
    }

    func clearRejectedDuplicateMessage() {
        rejectedDuplicateMessage = nil
    }

    func clearRejectedInvalidParticipantMessage() {
        rejectedInvalidParticipantMessage = nil
    }

    func clearBlockedRetapMessage() {
        blockedRetapMessage = nil
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
