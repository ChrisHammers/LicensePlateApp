//
//  TravelLogRepository.swift
//  LicensePlateApp
//
//  Projection of completed trip sessions for Travel Log. Step 03 — repository layer.
//  Composes TripSessionRepository and GameInstanceRepository; no direct entity access.
//

import Foundation
import SwiftData
import Combine

@MainActor
final class TravelLogRepository: ObservableObject, TravelLogRepositoryProtocol {

    static let shared = TravelLogRepository(
        tripSessionRepository: TripSessionRepository.shared,
        gameInstanceRepository: GameInstanceRepository.shared
    )

    private let tripSessionRepository: TripSessionRepositoryProtocol
    private let gameInstanceRepository: GameInstanceRepositoryProtocol

    init(tripSessionRepository: TripSessionRepositoryProtocol, gameInstanceRepository: GameInstanceRepositoryProtocol) {
        self.tripSessionRepository = tripSessionRepository
        self.gameInstanceRepository = gameInstanceRepository
    }

    func setModelContext(_ context: ModelContext) {
        // No-op: session and game repos receive context from RootView/ContentView.
    }

    // MARK: - Completed sessions (domain)

    func fetchCompletedSessions(userId: String?, limit: Int) throws -> [TripSession] {
        try tripSessionRepository.loadArchivedSessions(
            userId: userId,
            limit: limit,
            includeCancelled: false,
            sortBy: .endedAtDesc
        )
    }

    // MARK: - Summary projections (TravelLogEntry)

    func getSummaryProjections(userId: String?, sortBy: TravelLogSort, limit: Int, statusFilter: TravelLogStatusFilter = .endedOnly) throws -> [TravelLogEntry] {
        let sessions = try tripSessionRepository.loadArchivedSessions(
            userId: userId,
            limit: limit,
            includeCancelled: statusFilter == .endedAndCancelled,
            sortBy: sortBy
        )
        var entries: [TravelLogEntry] = []
        for session in sessions {
            guard let endedAt = session.endedAt else { continue }
            let participantCount = session.participants.count
            let gameCount = try gameInstanceRepository.gameCount(sessionId: session.id)
            let summary = participantCount > 0
                ? "\(participantCount) participant(s)"
                : "Trip completed"
            entries.append(TravelLogEntry(
                id: session.id.uuidString,
                sessionId: session.id,
                tripName: session.name,
                endedAt: endedAt,
                summary: summary,
                locationMetadata: nil,
                participantCount: participantCount,
                gameCount: gameCount,
                status: session.status
            ))
        }
        return entries
    }
}

enum TravelLogRepositoryError: Error, LocalizedError {
    case noModelContext

    var errorDescription: String? {
        switch self {
        case .noModelContext: return "Model context not set"
        }
    }
}
