//
//  TripSessionViewModel.swift
//  LicensePlateApp
//
//  Step 6.8 — ViewModel for trip dashboard. Loads session + games; exposes game row items for list. No persistence in view.
//

import Foundation
import Combine
import FirebaseAuth

/// Lightweight row data for one game in the trip session list.
struct GameRowItem: Identifiable {
    var id: UUID { gameId }
    let gameId: UUID
    let definitionId: String
    let title: String
    let gameTypeDisplay: String
    let progressSummary: String
    /// True when lifecycle is `.started` (in-progress pill on trip dashboard).
    let showsInProgressIndicator: Bool
    /// Localized collaborative / competitive (game-scoped).
    let gameModeDisplay: String
    /// Nil when the game has no teams.
    let teamSummary: String?
    /// True when user can tap to enter this game (e.g. license plate).
    let isEnterable: Bool
}

@MainActor
final class TripSessionViewModel: ObservableObject {

    @Published private(set) var session: TripSession?
    @Published private(set) var gameRowItems: [GameRowItem] = []
    /// Trip-wide competitive standings (same projection as Travel Log summary). Empty when not applicable or unavailable.
    @Published private(set) var tripLeaderboardRows: [RankedParticipantContribution] = []
    /// True when the trip has at least one competitive game and leaderboard rows were built successfully.
    @Published private(set) var showsTripCompetitiveLeaderboard: Bool = false
    /// Unique configured plate regions found anywhere on the trip (any participant, any game).
    @Published private(set) var tripFoundCount: Int = 0
    /// Unique union of configured target region IDs across all license-plate games on the trip.
    @Published private(set) var tripTotalCount: Int = 0
    /// Region IDs shown as found on the trip map (unique, configured-scope).
    @Published private(set) var tripFoundRegionIDs: [String] = []
    /// One representative `FoundRegion` per unique found region (earliest active discovery).
    @Published private(set) var tripFoundRegions: [FoundRegion] = []
    /// Countries covered by the trip-wide configured plate scope (for map framing).
    @Published private(set) var tripEnabledCountries: [PlateRegion.Country] = []
    /// Finder identity snapshots for where-found pin attribution on the trip map.
    @Published private(set) var tripFinderIdentitiesByUserId: [String: UserRepository.UserIdentitySnapshot] = [:]
    @Published var errorMessage: String?

    private let sessionId: UUID
    private let tripSessionRepository: TripSessionRepositoryProtocol
    private let gameInstanceRepository: GameInstanceRepositoryProtocol
    private let tripActivityEventRepository: TripActivityEventRepositoryProtocol?
    private let lifecycleService: TripSessionLifecycleServiceProtocol
    private let authService: FirebaseAuthService
    private let routeTrackingService: TripRouteTrackingService
    private let participantPrefsStore: TripParticipantPrefsStore
    private let appPrefsStore: AppPrefsStore
    private var didLogTripDashboardLeaderboard = false
    private var cancellables = Set<AnyCancellable>()
    /// One-time bootstrap merge per distinct roster (listeners handle ongoing updates).
    private var lastRosterProfileBootstrapSignature: String?
    /// One-time remote participant-preference load per signed-in viewer.
    private var lastParticipantPrefsBootstrapUserId: String?

    var isTripCreator: Bool {
        guard let session else { return false }
        return isTripCreator(for: session)
    }

    /// Trip container is in progress (driver has started the trip).
    var isTripContainerActive: Bool {
        guard let session else { return false }
        return session.status == .active && session.startedAt != nil
    }

    /// Driver-only; trip must be active (started and not ended/cancelled).
    var canEndTrip: Bool {
        isTripCreator && isTripContainerActive
    }

    var canAddGame: Bool {
        guard let session else { return false }
        guard isTripCreator else { return false }
        guard session.status != .ended, session.status != .cancelled else { return false }
        return canAddLicensePlateGame(existingGames: sessionGamesForAddGameCheck())
    }

    var addGameAccessibilityHint: String {
        if !isTripCreator {
            return "Only the Driver can add a game".localized
        }
        if let session, session.status == .ended || session.status == .cancelled {
            return "This trip can't be changed anymore.".localized
        }
       
        if !canAddLicensePlateGame(existingGames: sessionGamesForAddGameCheck()) {
            return "End the current license plate game before adding another.".localized
        }
        return "Adds another license plate game to this trip".localized
    }

    var endTripAccessibilityHint: String {
        if isTripCreator {
            return "Ends the trip and all open games".localized
        }
        return "Only the Driver can end the trip".localized
    }

    init(
        sessionId: UUID,
        tripSessionRepository: TripSessionRepositoryProtocol,
        gameInstanceRepository: GameInstanceRepositoryProtocol,
        tripActivityEventRepository: TripActivityEventRepositoryProtocol? = nil,
        lifecycleService: TripSessionLifecycleServiceProtocol = TripSessionLifecycleService.shared,
        authService: FirebaseAuthService,
        routeTrackingService: TripRouteTrackingService = .shared,
        participantPrefsStore: TripParticipantPrefsStore = .shared,
        appPrefsStore: AppPrefsStore = .shared
    ) {
        self.sessionId = sessionId
        self.tripSessionRepository = tripSessionRepository
        self.gameInstanceRepository = gameInstanceRepository
        self.tripActivityEventRepository = tripActivityEventRepository
        self.lifecycleService = lifecycleService
        self.authService = authService
        self.routeTrackingService = routeTrackingService
        self.participantPrefsStore = participantPrefsStore
        self.appPrefsStore = appPrefsStore
        self.session = try? tripSessionRepository.session(byId: sessionId)

        TripCanonicalRemoteSyncService.shared.hydrationSignal
            .filter { [weak self] hydratedId in
                guard let self else { return false }
                return hydratedId == self.sessionId
            }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.load()
            }
            .store(in: &cancellables)
    }

    func load() {
        errorMessage = nil
        showsTripCompetitiveLeaderboard = false
        tripLeaderboardRows = []
        do {
            guard let s = try tripSessionRepository.session(byId: sessionId) else {
                session = nil
                gameRowItems = []
                clearTripPlateProjection()
                lastRosterProfileBootstrapSignature = nil
                lastParticipantPrefsBootstrapUserId = nil
                let selfUid = Auth.auth().currentUser?.uid
                UserProfileListenCoordinator.shared.setPinnedUsers(selfUserId: selfUid, rosterUserIds: [])
                return
            }
            session = s
            bootstrapParticipantLocationState(for: s)
            syncPinnedUserProfileListenersAndBootstrapRosterIfNeeded(for: s)
            if s.mode == .multiplayer {
                TripCanonicalRemoteSyncService.shared.startIncrementalListeningIfNeeded(sessionId: sessionId)
            }
            let games = (try? gameInstanceRepository.fetchByTripSession(sessionId: sessionId)) ?? []
            var rows: [GameRowItem] = []
            for game in games {
                let discoveries = tripActivityEventRepository.flatMap { repo in
                    (try? repo.discoveries(sessionId: sessionId, gameInstanceId: game.id)) ?? []
                } ?? []
                let goal = game.licensePlateConfig().map { LicensePlateScopeCalculator.completionGoal(for: $0) }
                let foundCount: Int = {
                    if let config = game.licensePlateConfig() {
                        return LicensePlateScopeCalculator.scopedUniqueFoundCount(
                            discoveries: discoveries,
                            config: config
                        )
                    }
                    return discoveries.count
                }()
                let progressSummary: String
                if let g = goal {
                    progressSummary = "\(foundCount)/\(g)"
                } else {
                    progressSummary = "\(foundCount)"
                }
                let lifecycleState = game.commonConfig.lifecycleState
                let gameTypeDisplay = GameType(rawValue: game.definitionId)?.displayName ?? game.definitionId
                let title = gameTypeDisplay
                let isEnterable = game.definitionId == GameType.licensePlate.rawValue
                let modeDisplay = game.commonConfig.gameMode.localizedDisplayName
                let teamsLine = Self.teamSummary(for: game.teams)
                rows.append(GameRowItem(
                    gameId: game.id,
                    definitionId: game.definitionId,
                    title: title,
                    gameTypeDisplay: gameTypeDisplay,
                    progressSummary: progressSummary,
                    showsInProgressIndicator: lifecycleState.showsInProgressIndicator,
                    gameModeDisplay: modeDisplay,
                    teamSummary: teamsLine,
                    isEnterable: isEnterable
                ))
            }
            gameRowItems = rows

            refreshTripPlateProjection(games: games)
            refreshTripLeaderboard(session: s, games: games)
        } catch {
            errorMessage = error.localizedDescription
            session = nil
            gameRowItems = []
            clearTripPlateProjection()
            showsTripCompetitiveLeaderboard = false
            tripLeaderboardRows = []
            lastRosterProfileBootstrapSignature = nil
            lastParticipantPrefsBootstrapUserId = nil
            let selfUid = Auth.auth().currentUser?.uid
            UserProfileListenCoordinator.shared.setPinnedUsers(selfUserId: selfUid, rosterUserIds: [])
        }
    }

    /// Ends the trip via canonical lifecycle (closes open games, records events, syncs). Driver-only; call from confirmation UI.
    func endTrip() throws {
        guard canEndTrip else {
            throw TripSessionViewModelError.endTripNotAllowed
        }
        let endedBy = authService.currentUser?.firebaseUID ?? authService.currentUser?.id
        try lifecycleService.endTrip(sessionId: sessionId, endedBy: endedBy)
        load()
    }

    private func rosterUserIds(for session: TripSession) -> Set<String> {
        var ids = Set(session.participants.map(\.userId).filter { !$0.isEmpty })
        if let createdBy = session.createdBy, !createdBy.isEmpty {
            ids.insert(createdBy)
        }
        return ids
    }

    private func bootstrapParticipantLocationState(for session: TripSession) {
        let viewerId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id ?? ""
        routeTrackingService.resumeIfActive(
            session: session,
            viewerUserId: viewerId.isEmpty ? nil : viewerId
        )

        guard !viewerId.isEmpty, lastParticipantPrefsBootstrapUserId != viewerId else { return }
        lastParticipantPrefsBootstrapUserId = viewerId
        Task { @MainActor [participantPrefsStore, appPrefsStore] in
            let fallback = appPrefsStore.participationDefaults.asParticipantPrefs()
            await participantPrefsStore.load(
                sessionId: session.id,
                userId: viewerId,
                fallback: fallback,
                backfillIfMissing: true
            )
        }
    }

    private func syncPinnedUserProfileListenersAndBootstrapRosterIfNeeded(for session: TripSession) {
        let roster = rosterUserIds(for: session)
        let selfUid = Auth.auth().currentUser?.uid
        UserProfileListenCoordinator.shared.setPinnedUsers(
            selfUserId: selfUid,
            rosterUserIds: roster
        )

        let signature = roster.sorted().joined(separator: "\u{1e}")
        guard signature != lastRosterProfileBootstrapSignature else { return }
        lastRosterProfileBootstrapSignature = signature

        guard !roster.isEmpty else { return }
        Task {
            await UserRepository.shared.refreshUsersFromFirestoreIfPresent(userIds: roster)
        }
    }

    /// Trip-wide leaderboard from canonical `TripSummaryBuilder` path (competitive games only).
    private func refreshTripLeaderboard(session: TripSession, games: [GameInstance]) {
        guard games.contains(where: { $0.commonConfig.gameMode == .competitive }) else {
            showsTripCompetitiveLeaderboard = false
            tripLeaderboardRows = []
            return
        }
        guard let eventRepo = tripActivityEventRepository else {
            showsTripCompetitiveLeaderboard = false
            tripLeaderboardRows = []
            return
        }
        do {
            let discoveries = try eventRepo.discoveries(sessionId: sessionId, gameInstanceId: nil)
            let summary = TripSummaryBuilder.build(session: session, games: games, discoveries: discoveries)
            tripLeaderboardRows = summary.rankedParticipants
            showsTripCompetitiveLeaderboard = true
            if session.mode == .multiplayer, !didLogTripDashboardLeaderboard {
                AnalyticsService.shared.log(.tripDashboardCompetitiveLeaderboardPresented(tripSessionId: sessionId.uuidString))
                didLogTripDashboardLeaderboard = true
            }
        } catch {
            showsTripCompetitiveLeaderboard = false
            tripLeaderboardRows = []
        }
    }

    /// Unique configured plate progress across all license-plate games on the trip.
    /// Same region in two games or found by two participants counts once; any active find marks it found.
    private func refreshTripPlateProjection(games: [GameInstance]) {
        let lpGames = games.filter { $0.definitionId == GameType.licensePlate.rawValue }
        var configuredIds = Set<String>()
        for game in lpGames {
            let config = game.licensePlateConfig() ?? LicensePlateGameConfig()
            configuredIds.formUnion(LicensePlateScopeCalculator.targetRegionIds(for: config))
        }

        guard !configuredIds.isEmpty else {
            clearTripPlateProjection()
            return
        }

        let lpGameIds = Set(lpGames.map(\.id))
        let discoveries: [GameDiscovery]
        if let eventRepo = tripActivityEventRepository {
            discoveries = ((try? eventRepo.discoveries(sessionId: sessionId, gameInstanceId: nil)) ?? [])
                .filter { lpGameIds.contains($0.gameInstanceId) }
        } else {
            discoveries = []
        }

        var earliestByRegion: [String: GameDiscovery] = [:]
        for discovery in discoveries.sorted(by: GameDiscovery.orderingAscending) {
            if earliestByRegion[discovery.targetId] == nil {
                earliestByRegion[discovery.targetId] = discovery
            }
        }

        let foundIds = configuredIds.filter { earliestByRegion[$0] != nil }.sorted()
        let representatives: [FoundRegion] = foundIds.compactMap { regionId in
            guard let discovery = earliestByRegion[regionId] else { return nil }
            return FoundRegion(
                regionID: discovery.targetId,
                foundAt: discovery.discoveredAt,
                inputMethod: discovery.inputMethod,
                foundBy: discovery.participantId.isEmpty ? nil : discovery.participantId,
                foundAtLocation: discovery.location
            )
        }

        tripTotalCount = configuredIds.count
        tripFoundCount = foundIds.count
        tripFoundRegionIDs = foundIds
        tripFoundRegions = representatives
        tripEnabledCountries = Array(
            Set(PlateRegion.all.filter { configuredIds.contains($0.id) }.map(\.country))
        ).sorted { $0.rawValue < $1.rawValue }

        let finderIds = Set(representatives.compactMap(\.foundBy).filter { !$0.isEmpty })
        tripFinderIdentitiesByUserId = finderIds.isEmpty
            ? [:]
            : UserRepository.shared.cachedIdentityMap(forUserIds: finderIds)
    }

    private func clearTripPlateProjection() {
        tripFoundCount = 0
        tripTotalCount = 0
        tripFoundRegionIDs = []
        tripFoundRegions = []
        tripEnabledCountries = []
        tripFinderIdentitiesByUserId = [:]
    }

    private func isTripCreator(for session: TripSession) -> Bool {
        let uid = authService.currentUser?.firebaseUID ?? authService.currentUser?.id
        guard let uid, let createdBy = session.createdBy else { return false }
        return createdBy == uid
    }

    private func sessionGamesForAddGameCheck() -> [GameInstance] {
        (try? gameInstanceRepository.fetchByTripSession(sessionId: sessionId)) ?? []
    }

    private func canAddLicensePlateGame(existingGames: [GameInstance]) -> Bool {
        (try? GameplayLifecycleRules.validateCanAddGame(
            ofType: GameType.licensePlate.rawValue,
            existingGames: existingGames
        )) != nil
    }

    /// Matches `TripSummaryBuilder` team line for list UI.
    private static func teamSummary(for teams: [TripTeam]) -> String? {
        guard !teams.isEmpty else { return nil }
        if teams.count == 1 {
            let name = teams[0].name.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? "1 team".localized : name
        }
        return "%d teams".localized(teams.count)
    }
}

enum TripSessionViewModelError: LocalizedError, Equatable {
    case endTripNotAllowed

    var errorDescription: String? {
        switch self {
        case .endTripNotAllowed:
            return "Only the Driver can end the trip".localized
        }
    }
}
