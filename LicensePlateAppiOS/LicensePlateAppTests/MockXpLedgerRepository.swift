//
//  MockXpLedgerRepository.swift
//  LicensePlateAppTests
//

import Foundation
import SwiftData
@testable import LicensePlateApp

@MainActor
final class MockXpLedgerRepository: XpLedgerRepositoryProtocol {
    var stored: [XpLedgerEvent] = []

    func setModelContext(_ context: ModelContext) {}

    func append(_ event: XpLedgerEvent) throws {
        stored.append(event)
    }

    func appendBaseDiscoveryIfAbsent(_ event: XpLedgerEvent) throws -> Bool {
        if stored.contains(where: {
            $0.xpUniquenessKey == event.xpUniquenessKey
                && $0.status != .voided
                && ($0.grantKind == .provisionalDiscoveryXp || $0.grantKind == .finalDiscoveryAward)
        }) {
            return false
        }
        stored.append(event)
        return true
    }

    func ledgerEvents(userId: String, sessionId: UUID, gameInstanceId: UUID, itemId: String?) throws -> [XpLedgerEvent] {
        try ledgerEvents(userId: userId, sessionId: sessionId, gameInstanceId: gameInstanceId, itemId: itemId, statuses: nil)
    }

    func ledgerEvents(
        userId: String,
        sessionId: UUID,
        gameInstanceId: UUID,
        itemId: String?,
        statuses: Set<XpLedgerStatus>?
    ) throws -> [XpLedgerEvent] {
        let filtered = stored.filter { row in
            guard row.userId == userId, row.sessionId == sessionId, row.gameInstanceId == gameInstanceId else { return false }
            if let itemId {
                return row.itemId == itemId
            }
            return true
        }
        if let statuses {
            return filtered.filter { statuses.contains($0.status) }.sorted(by: sortLedger)
        }
        return filtered.sorted(by: sortLedger)
    }

    func ledgerEvents(forUniquenessKey key: String) throws -> [XpLedgerEvent] {
        stored.filter { $0.xpUniquenessKey == key }.sorted(by: sortLedger)
    }

    func ledgerEvents(sourceEventId: String) throws -> [XpLedgerEvent] {
        stored.filter { $0.sourceEventId == sourceEventId }.sorted(by: sortLedger)
    }

    func ledgerEvents(userId: String) throws -> [XpLedgerEvent] {
        stored.filter { $0.userId == userId }.sorted(by: sortLedger)
    }

    func ledgerEvents(userId: String, sessionId: UUID) throws -> [XpLedgerEvent] {
        stored.filter { $0.userId == userId && $0.sessionId == sessionId }.sorted(by: sortLedger)
    }

    func netXpDelta(
        userId: String,
        sessionId: UUID,
        gameInstanceId: UUID,
        itemId: String?,
        includingStatuses: Set<XpLedgerStatus>
    ) throws -> Int {
        try ledgerEvents(userId: userId, sessionId: sessionId, gameInstanceId: gameInstanceId, itemId: itemId, statuses: includingStatuses)
            .reduce(0) { $0 + $1.xpDelta }
    }

    func hasBaseDiscoveryForUniquenessKey(_ key: String) throws -> Bool {
        stored.contains {
            $0.xpUniquenessKey == key
                && $0.status != .voided
                && ($0.grantKind == .provisionalDiscoveryXp || $0.grantKind == .finalDiscoveryAward)
        }
    }

    @discardableResult
    func voidProvisionalRows(forUniquenessKey key: String, resolvedAt: Date) throws -> Int {
        var sum = 0
        for index in stored.indices where stored[index].xpUniquenessKey == key && stored[index].status == .provisional {
            sum += stored[index].xpDelta
            stored[index].status = .voided
            stored[index].resolvedAt = resolvedAt
        }
        return sum
    }

    private func sortLedger(_ a: XpLedgerEvent, _ b: XpLedgerEvent) -> Bool {
        if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
        return a.id < b.id
    }
}
