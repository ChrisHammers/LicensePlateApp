//
//  TravelLogRepository.swift
//  LicensePlateApp
//
//  Projection of completed trip sessions for Travel Log. Step 03 — repository layer.
//

import Foundation
import SwiftData
import Combine

@MainActor
final class TravelLogRepository: ObservableObject, TravelLogRepositoryProtocol {

    static let shared = TravelLogRepository()

    private var modelContext: ModelContext?

    private init() {}

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    // MARK: - Completed sessions (domain)

    func fetchCompletedSessions(userId: String?, limit: Int) throws -> [TripSession] {
        guard let ctx = modelContext else { throw TravelLogRepositoryError.noModelContext }
        let ended = TripStatus.ended.rawValue
        var descriptor = FetchDescriptor<TripSessionEntity>(
            predicate: #Predicate<TripSessionEntity> { $0.status == ended }
        )
        descriptor.sortBy = [SortDescriptor(\.endedAt, order: .reverse)]
        descriptor.fetchLimit = limit
        var entities = try ctx.fetch(descriptor)
        if let uid = userId {
            entities = entities.filter { entity in
                entity.createdBy == uid || participantIds(from: entity.participantsData).contains(uid)
            }
        }
        return entities.map { TripSessionEntityMapper.toDomain($0) }
    }

    // MARK: - Summary projections (TravelLogEntry)

    func getSummaryProjections(userId: String?, sortBy: TravelLogSort, limit: Int) throws -> [TravelLogEntry] {
        guard let ctx = modelContext else { throw TravelLogRepositoryError.noModelContext }
        let ended = TripStatus.ended.rawValue
        var descriptor = FetchDescriptor<TripSessionEntity>(
            predicate: #Predicate<TripSessionEntity> { $0.status == ended }
        )
        switch sortBy {
        case .endedAtDesc:
            descriptor.sortBy = [SortDescriptor(\.endedAt, order: .reverse)]
        case .endedAtAsc:
            descriptor.sortBy = [SortDescriptor(\.endedAt, order: .forward)]
        }
        descriptor.fetchLimit = limit
        var entities = try ctx.fetch(descriptor)
        if let uid = userId {
            entities = entities.filter { entity in
                entity.createdBy == uid || participantIds(from: entity.participantsData).contains(uid)
            }
        }
        return entities.compactMap { entity -> TravelLogEntry? in
            guard let endedAt = entity.endedAt,
                  let sessionId = UUID(uuidString: entity.id) else { return nil }
            let participantCount = participantIds(from: entity.participantsData).count
            let summary = participantCount > 0
                ? "\(participantCount) participant(s)"
                : "Trip completed"
            return TravelLogEntry(
                id: entity.id,
                sessionId: sessionId,
                tripName: entity.name,
                endedAt: endedAt,
                summary: summary,
                locationMetadata: nil
            )
        }
    }

    // MARK: - Helpers

    private func participantIds(from participantsData: Data?) -> Set<String> {
        guard let data = participantsData,
              let participants = try? JSONDecoder().decode([TripParticipant].self, from: data) else {
            return []
        }
        return Set(participants.map(\.userId))
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
