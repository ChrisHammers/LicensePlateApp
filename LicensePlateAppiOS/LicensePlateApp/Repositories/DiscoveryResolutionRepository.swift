//
//  DiscoveryResolutionRepository.swift
//  LicensePlateApp
//

import Foundation
import SwiftData
import Combine

enum DiscoveryResolutionRepositoryError: Error, Equatable {
    case noModelContext
}

@MainActor
final class DiscoveryResolutionRepository: ObservableObject, DiscoveryResolutionRepositoryProtocol {

    static let shared = DiscoveryResolutionRepository()

    private var modelContext: ModelContext?

    private init() {}

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func save(_ resolution: DiscoveryResolution) throws {
        guard let ctx = modelContext else { throw DiscoveryResolutionRepositoryError.noModelContext }
        let rid = resolution.resolutionId
        let descriptor = FetchDescriptor<DiscoveryResolutionEntity>(
            predicate: #Predicate<DiscoveryResolutionEntity> { $0.resolutionId == rid }
        )
        if let existing = try ctx.fetch(descriptor).first {
            let updated = XpLedgerMapper.toEntity(resolution)
            existing.sourceEventId = updated.sourceEventId
            existing.sessionId = updated.sessionId
            existing.gameInstanceId = updated.gameInstanceId
            existing.itemId = updated.itemId
            existing.actorUserId = updated.actorUserId
            existing.finalOutcome = updated.finalOutcome
            existing.tripScoringOutcome = updated.tripScoringOutcome
            existing.personalHistoryOutcome = updated.personalHistoryOutcome
            existing.finalXpAward = updated.finalXpAward
            existing.xpReason = updated.xpReason
            existing.resolvedAgainstEventId = updated.resolvedAgainstEventId
            existing.serverSequence = updated.serverSequence
            existing.resolutionVersion = updated.resolutionVersion
            existing.resolvedAtServer = updated.resolvedAtServer
        } else {
            ctx.insert(XpLedgerMapper.toEntity(resolution))
        }
        try ctx.save()
    }

    func resolution(bySourceEventId sourceEventId: String) throws -> DiscoveryResolution? {
        guard let ctx = modelContext else { throw DiscoveryResolutionRepositoryError.noModelContext }
        let descriptor = FetchDescriptor<DiscoveryResolutionEntity>(
            predicate: #Predicate<DiscoveryResolutionEntity> { $0.sourceEventId == sourceEventId }
        )
        let rows = try ctx.fetch(descriptor)
        guard !rows.isEmpty else { return nil }
        let best = rows.max(by: { lhs, rhs in
            if lhs.serverSequence != rhs.serverSequence { return lhs.serverSequence < rhs.serverSequence }
            return lhs.resolutionVersion < rhs.resolutionVersion
        })!
        return try XpLedgerMapper.toDomain(best)
    }

    func resolutions(sessionId: UUID, gameInstanceId: UUID, itemId: String) throws -> [DiscoveryResolution] {
        guard let ctx = modelContext else { throw DiscoveryResolutionRepositoryError.noModelContext }
        let sid = sessionId.uuidString
        let gid = gameInstanceId.uuidString
        let descriptor = FetchDescriptor<DiscoveryResolutionEntity>(
            predicate: #Predicate<DiscoveryResolutionEntity> { e in
                e.sessionId == sid && e.gameInstanceId == gid && e.itemId == itemId
            }
        )
        let rows = try ctx.fetch(descriptor)
        let mapped = try rows.map { try XpLedgerMapper.toDomain($0) }
        return mapped.sorted {
            if $0.serverSequence != $1.serverSequence { return $0.serverSequence < $1.serverSequence }
            return $0.resolutionId < $1.resolutionId
        }
    }
}
