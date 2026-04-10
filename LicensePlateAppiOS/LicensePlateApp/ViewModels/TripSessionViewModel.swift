//
//  TripSessionViewModel.swift
//  LicensePlateApp
//
//  Step 6.8 — ViewModel for trip dashboard. Loads session + games; exposes game row items for list. No persistence in view.
//

import Foundation
import Combine

/// Lightweight row data for one game in the trip session list.
struct GameRowItem: Identifiable {
    var id: UUID { gameId }
    let gameId: UUID
    let definitionId: String
    let title: String
    let statusOrLifecycle: String
    let progressSummary: String
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
    @Published var errorMessage: String?

    private let sessionId: UUID
    private let tripSessionRepository: TripSessionRepositoryProtocol
    private let gameInstanceRepository: GameInstanceRepositoryProtocol
    private let tripActivityEventRepository: TripActivityEventRepositoryProtocol?
    private let gameInstanceLifecycleService: GameInstanceLifecycleServiceProtocol
    private var didLogTripDashboardLeaderboard = false
    private var cancellables = Set<AnyCancellable>()

    init(
        sessionId: UUID,
        tripSessionRepository: TripSessionRepositoryProtocol,
        gameInstanceRepository: GameInstanceRepositoryProtocol,
        tripActivityEventRepository: TripActivityEventRepositoryProtocol? = nil,
        gameInstanceLifecycleService: GameInstanceLifecycleServiceProtocol = GameInstanceLifecycleService.shared
    ) {
        self.sessionId = sessionId
        self.tripSessionRepository = tripSessionRepository
        self.gameInstanceRepository = gameInstanceRepository
        self.tripActivityEventRepository = tripActivityEventRepository
        self.gameInstanceLifecycleService = gameInstanceLifecycleService

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
                return
            }
            session = s
            if s.mode == .multiplayer {
                TripCanonicalRemoteSyncService.shared.startIncrementalListeningIfNeeded(sessionId: sessionId)
            }
            let games = (try? gameInstanceRepository.fetchByTripSession(sessionId: sessionId)) ?? []
            var rows: [GameRowItem] = []
            for game in games {
                let discoveryCount = tripActivityEventRepository.flatMap { repo in
                    (try? repo.discoveries(sessionId: sessionId, gameInstanceId: game.id))?.count ?? 0
                } ?? 0
                let goal = game.licensePlateConfig().map { LicensePlateScopeCalculator.completionGoal(for: $0) }
                let progressSummary: String
                if let g = goal {
                    progressSummary = "\(discoveryCount)/\(g)"
                } else {
                    progressSummary = "\(discoveryCount)"
                }
                let lifecycle = game.commonConfig.lifecycleState.rawValue
                let title = GameType(rawValue: game.definitionId)?.displayName ?? game.definitionId
                let isEnterable = game.definitionId == GameType.licensePlate.rawValue
                let modeDisplay = game.commonConfig.gameMode.localizedDisplayName
                let teamsLine = Self.teamSummary(for: game.teams)
                rows.append(GameRowItem(
                    gameId: game.id,
                    definitionId: game.definitionId,
                    title: title,
                    statusOrLifecycle: lifecycle,
                    progressSummary: progressSummary,
                    gameModeDisplay: modeDisplay,
                    teamSummary: teamsLine,
                    isEnterable: isEnterable
                ))
            }
            gameRowItems = rows

            refreshTripLeaderboard(session: s, games: games)
        } catch {
            errorMessage = error.localizedDescription
            session = nil
            gameRowItems = []
            showsTripCompetitiveLeaderboard = false
            tripLeaderboardRows = []
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

    /// Adds another license plate game, cloning mode/teams/scope from the first LP game on the trip (defaults if none).
    func addGame() {
        do {
            guard let session = try tripSessionRepository.session(byId: sessionId) else {
                errorMessage = nil
                self.session = nil
                gameRowItems = []
                showsTripCompetitiveLeaderboard = false
                tripLeaderboardRows = []
                return
            }
            if session.status == .ended || session.status == .cancelled {
                errorMessage = "This trip can’t be changed anymore.".localized
                return
            }

            let games = try gameInstanceRepository.fetchByTripSession(sessionId: sessionId)
            let template = games.first { $0.definitionId == GameType.licensePlate.rawValue }
            let choice = GameSetupChoice(
                gameType: .licensePlate,
                gameMode: template?.commonConfig.gameMode ?? .collaborative,
                teams: template?.teams ?? []
            )
            let lpConfig = template?.licensePlateConfig()
            let config = CombinedGameConfiguration(enabledGameTypes: [.licensePlate])
            let assembled = CombinedGameAssembler.assemble(
                session: session,
                config: config,
                choicesByGameType: [.licensePlate: choice],
                licensePlateConfig: lpConfig
            )
            guard let instance = assembled.first else {
                errorMessage = "Could not add game.".localized
                return
            }
            try gameInstanceRepository.create(instance: instance)

            let order = games.count + 1
            AnalyticsService.shared.log(.gameInstanceCreated(
                gameInstanceId: instance.id.uuidString,
                gameType: instance.definitionId,
                gameMode: instance.commonConfig.gameMode.rawValue,
                tripId: sessionId.uuidString,
                gameOrderInTrip: order
            ))

            var startGameError: String?
            if session.status == .active, session.startedAt != nil {
                do {
                    try gameInstanceLifecycleService.startGame(sessionId: sessionId, gameInstanceId: instance.id)
                } catch {
                    startGameError = error.localizedDescription
                }
            }

            load()
            if let startGameError {
                errorMessage = startGameError
            }
            // Runtime-proven: server `appendTripActivityEvent` returns "game not found" until `games/{id}` exists on Firestore (publishTripCanonicalState).
            Task { @MainActor in
                try? await TripCanonicalRemoteSyncService.shared.publishFullSession(sessionId: sessionId)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
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
