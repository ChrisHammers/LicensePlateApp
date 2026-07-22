//
//  XpLedgerRepository.swift
//  LicensePlateApp
//
//  Append-only XP ledger. No updates or deletes of existing rows.
//

import Foundation
import SwiftData
import Combine

enum XpLedgerRepositoryError: Error, Equatable {
    case noModelContext
    case appendBaseDiscoveryRequiresProvisionalOrFinalKind
}

@MainActor
final class XpLedgerRepository: ObservableObject, XpLedgerRepositoryProtocol {

    static let shared = XpLedgerRepository()

    private var modelContext: ModelContext?

    private init() {}

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func append(_ event: XpLedgerEvent) throws {
        guard let ctx = modelContext else { throw XpLedgerRepositoryError.noModelContext }
        ctx.insert(XpLedgerMapper.toEntity(event))
        try ctx.save()
        objectWillChange.send()
    }

    func appendBaseDiscoveryIfAbsent(_ event: XpLedgerEvent) throws -> Bool {
        guard event.grantKind == .provisionalDiscoveryXp || event.grantKind == .finalDiscoveryAward else {
            throw XpLedgerRepositoryError.appendBaseDiscoveryRequiresProvisionalOrFinalKind
        }
        guard let ctx = modelContext else { throw XpLedgerRepositoryError.noModelContext }
        if try hasBaseDiscoveryForUniquenessKey(event.xpUniquenessKey) {
            return false
        }
        ctx.insert(XpLedgerMapper.toEntity(event))
        try ctx.save()
        objectWillChange.send()
        return true
    }

    func hasBaseDiscoveryForUniquenessKey(_ key: String) throws -> Bool {
        guard let ctx = modelContext else { throw XpLedgerRepositoryError.noModelContext }
        let descriptor = FetchDescriptor<XpLedgerEventEntity>(
            predicate: #Predicate<XpLedgerEventEntity> { entity in
                entity.xpUniquenessKey == key
                    && (entity.grantKind == "provisional_discovery_xp" || entity.grantKind == "final_discovery_award")
            }
        )
        let count = try ctx.fetchCount(descriptor)
        return count > 0
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
        guard let ctx = modelContext else { throw XpLedgerRepositoryError.noModelContext }
        let sid = sessionId.uuidString
        let gid = gameInstanceId.uuidString
        let rows: [XpLedgerEventEntity]
        if let itemId {
            let descriptor = FetchDescriptor<XpLedgerEventEntity>(
                predicate: #Predicate<XpLedgerEventEntity> { e in
                    e.userId == userId && e.sessionId == sid && e.gameInstanceId == gid && e.itemId == itemId
                }
            )
            rows = try ctx.fetch(descriptor)
        } else {
            let descriptor = FetchDescriptor<XpLedgerEventEntity>(
                predicate: #Predicate<XpLedgerEventEntity> { e in
                    e.userId == userId && e.sessionId == sid && e.gameInstanceId == gid
                }
            )
            rows = try ctx.fetch(descriptor)
        }
        return try sortedDomainEvents(from: rows, statuses: statuses)
    }

    func ledgerEvents(forUniquenessKey key: String) throws -> [XpLedgerEvent] {
        guard let ctx = modelContext else { throw XpLedgerRepositoryError.noModelContext }
        let descriptor = FetchDescriptor<XpLedgerEventEntity>(
            predicate: #Predicate<XpLedgerEventEntity> { $0.xpUniquenessKey == key }
        )
        let rows = try ctx.fetch(descriptor)
        return try sortedDomainEvents(from: rows, statuses: nil)
    }

    func ledgerEvents(sourceEventId: String) throws -> [XpLedgerEvent] {
        guard let ctx = modelContext else { throw XpLedgerRepositoryError.noModelContext }
        let descriptor = FetchDescriptor<XpLedgerEventEntity>(
            predicate: #Predicate<XpLedgerEventEntity> { $0.sourceEventId == sourceEventId }
        )
        let rows = try ctx.fetch(descriptor)
        return try sortedDomainEvents(from: rows, statuses: nil)
    }

    func ledgerEvents(userId: String) throws -> [XpLedgerEvent] {
        guard let ctx = modelContext else { throw XpLedgerRepositoryError.noModelContext }
        let descriptor = FetchDescriptor<XpLedgerEventEntity>(
            predicate: #Predicate<XpLedgerEventEntity> { e in
                e.userId == userId
            }
        )
        let rows = try ctx.fetch(descriptor)
        return try sortedDomainEvents(from: rows, statuses: nil)
    }

    func ledgerEvents(userId: String, sessionId: UUID) throws -> [XpLedgerEvent] {
        guard let ctx = modelContext else { throw XpLedgerRepositoryError.noModelContext }
        let sid = sessionId.uuidString
        let descriptor = FetchDescriptor<XpLedgerEventEntity>(
            predicate: #Predicate<XpLedgerEventEntity> { e in
                e.userId == userId && e.sessionId == sid
            }
        )
        let rows = try ctx.fetch(descriptor)
        return try sortedDomainEvents(from: rows, statuses: nil)
    }

    func netXpDelta(
        userId: String,
        sessionId: UUID,
        gameInstanceId: UUID,
        itemId: String?,
        includingStatuses: Set<XpLedgerStatus>
    ) throws -> Int {
        let events = try ledgerEvents(
            userId: userId,
            sessionId: sessionId,
            gameInstanceId: gameInstanceId,
            itemId: itemId,
            statuses: includingStatuses
        )
        return events.reduce(0) { $0 + $1.xpDelta }
    }

    /// Hard sign-out exception to append-only rule: wipe the local ledger.
    func deleteAllLocal() throws {
        guard let ctx = modelContext else { throw XpLedgerRepositoryError.noModelContext }
        try ctx.delete(model: XpLedgerEventEntity.self)
        try ctx.save()
        objectWillChange.send()
    }

    private func sortedDomainEvents(from rows: [XpLedgerEventEntity], statuses: Set<XpLedgerStatus>?) throws -> [XpLedgerEvent] {
        var mapped: [XpLedgerEvent] = []
        mapped.reserveCapacity(rows.count)
        for row in rows {
            let domain = try XpLedgerMapper.toDomain(row)
            if let statuses, !statuses.contains(domain.status) { continue }
            mapped.append(domain)
        }
        mapped.sort {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id < $1.id
        }
        return mapped
    }
}
