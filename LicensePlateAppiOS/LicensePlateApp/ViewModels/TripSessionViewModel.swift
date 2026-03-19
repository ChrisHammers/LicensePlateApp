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

    init(
        sessionId: UUID,
        tripSessionRepository: TripSessionRepositoryProtocol,
        gameInstanceRepository: GameInstanceRepositoryProtocol,
        tripActivityEventRepository: TripActivityEventRepositoryProtocol? = nil
    ) {
        self.sessionId = sessionId
        self.tripSessionRepository = tripSessionRepository
        self.gameInstanceRepository = gameInstanceRepository
        self.tripActivityEventRepository = tripActivityEventRepository
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

    /// Stub: Add game to this trip. TODO wire to add-game flow.
    func addGame() {
        // No-op for Step 6.8
    }
}
