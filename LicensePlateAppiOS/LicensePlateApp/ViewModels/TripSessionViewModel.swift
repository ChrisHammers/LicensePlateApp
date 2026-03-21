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
    /// True when user can tap to enter this game (e.g. license plate).
    let isEnterable: Bool
}

@MainActor
final class TripSessionViewModel: ObservableObject {

    @Published private(set) var session: TripSession?
    @Published private(set) var gameRowItems: [GameRowItem] = []
    @Published var errorMessage: String?

    private let sessionId: UUID
    private let tripSessionRepository: TripSessionRepositoryProtocol
    private let gameInstanceRepository: GameInstanceRepositoryProtocol
    private let tripActivityEventRepository: TripActivityEventRepositoryProtocol?
    private let gameInstanceLifecycleService: GameInstanceLifecycleServiceProtocol

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
    }

    func load() {
        errorMessage = nil
        do {
            guard let s = try tripSessionRepository.session(byId: sessionId) else {
                session = nil
                gameRowItems = []
                return
            }
            session = s
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
                rows.append(GameRowItem(
                    gameId: game.id,
                    definitionId: game.definitionId,
                    title: title,
                    statusOrLifecycle: lifecycle,
                    progressSummary: progressSummary,
                    isEnterable: isEnterable
                ))
            }
            gameRowItems = rows
        } catch {
            errorMessage = error.localizedDescription
            session = nil
            gameRowItems = []
        }
    }

    /// Adds another license plate game, cloning mode/teams/scope from the first LP game on the trip (defaults if none).
    func addGame() {
        do {
            guard let session = try tripSessionRepository.session(byId: sessionId) else {
                errorMessage = nil
                self.session = nil
                gameRowItems = []
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
