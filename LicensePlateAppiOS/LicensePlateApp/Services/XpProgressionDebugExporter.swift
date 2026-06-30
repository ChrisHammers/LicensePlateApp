//
//  XpProgressionDebugExporter.swift
//  LicensePlateApp
//
//  DEBUG — JSON snapshot of server progression, effective totals, and local XP ledger.
//

import Foundation

#if DEBUG

enum XpProgressionDebugExporter {

    struct SessionContext: Sendable, Equatable {
        var sessionId: UUID
        var gameInstanceId: UUID
        var sessionProgressionPending: ProgressionPendingDelta
        var sessionLedgerNetXp: Int
        var gameLedgerNetXp: Int
    }

    struct Payload: Codable, Sendable {
        struct DisplayedXp: Codable, Sendable {
            var serverTotal: Int
            var ledgerProvisionalPending: Int
            var profileDisplayedTotal: Int
            var effectiveTotal: Int?
            var effectivePendingDelta: Int?
        }

        struct ServerProgression: Codable, Sendable {
            var totalXp: Int
            var acceptedRegionFindCount: Int
            var competitiveFirstPlaceFinishes: Int
            var everCompetitiveFirstPlace: Bool
            var lastUpdatedAt: String?
            var appliedProgressionEventIds: [String]
        }

        struct EffectiveTotals: Codable, Sendable {
            var totalXp: Int
            var acceptedRegionFindCount: Int
            var competitiveFirstPlaceFinishes: Int
            var everCompetitiveFirstPlace: Bool
            var hasPendingLocalProgression: Bool
        }

        struct SessionContextPayload: Codable, Sendable {
            var sessionId: String
            var gameInstanceId: String
            var sessionProgressionPending: PendingDeltaPayload
            var sessionLedgerNetXp: Int
            var gameLedgerNetXp: Int
        }

        struct PendingDeltaPayload: Codable, Sendable {
            var totalXp: Int
            var acceptedRegionFindCount: Int
            var competitiveFirstPlaceFinishes: Int
            var everCompetitiveFirstPlace: Bool
        }

        struct LedgerSummary: Codable, Sendable {
            var eventCount: Int
            var netXpAllRows: Int
            var provisionalSum: Int
            var finalStatusSum: Int
        }

        struct LedgerRow: Codable, Sendable {
            var id: String
            var sessionId: String
            var gameInstanceId: String
            var sourceEventId: String
            var sourceEventType: String
            var itemId: String
            var grantKind: String
            var status: String
            var xpDelta: Int
            var reasonCode: String
            var xpUniquenessKey: String
            var createdAt: String
            var resolvedAt: String?
            var metadata: [String: String]?
        }

        var exportedAt: String
        var userId: String
        var displayedXp: DisplayedXp
        var serverProgression: ServerProgression?
        var effectiveTotals: EffectiveTotals?
        var sessionContext: SessionContextPayload?
        var ledgerSummary: LedgerSummary
        var ledgerEvents: [LedgerRow]
    }

    @MainActor
    static func buildPayload(
        userId: String,
        sessionContext: SessionContext? = nil
    ) throws -> Payload {
        guard !userId.isEmpty else {
            throw ExportError.missingUserId
        }

        let server = UserProgressionRepository.shared.snapshot
        let effective = UserProgressionService.shared.effectiveTotals
        let allLedger = (try? XpLedgerRepository.shared.ledgerEvents(userId: userId)) ?? []
        let provisionalPending = LedgerPendingXpTotals.fromLedgerEvents(allLedger).provisionalSum
        let serverTotal = server?.totalXp ?? 0
        let serverForDelta = server ?? UserProgressionSnapshot.empty
        let effectivePendingDelta = effective.map { $0.totalXp - serverForDelta.totalXp }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return Payload(
            exportedAt: iso.string(from: Date()),
            userId: userId,
            displayedXp: Payload.DisplayedXp(
                serverTotal: serverTotal,
                ledgerProvisionalPending: provisionalPending,
                profileDisplayedTotal: serverTotal + provisionalPending,
                effectiveTotal: effective?.totalXp,
                effectivePendingDelta: effectivePendingDelta
            ),
            serverProgression: server.map {
                Payload.ServerProgression(
                    totalXp: $0.totalXp,
                    acceptedRegionFindCount: $0.acceptedRegionFindCount,
                    competitiveFirstPlaceFinishes: $0.competitiveFirstPlaceFinishes,
                    everCompetitiveFirstPlace: $0.everCompetitiveFirstPlace,
                    lastUpdatedAt: $0.lastUpdatedAt.map { iso.string(from: $0) },
                    appliedProgressionEventIds: $0.appliedProgressionEventIds.sorted()
                )
            },
            effectiveTotals: effective.map {
                Payload.EffectiveTotals(
                    totalXp: $0.totalXp,
                    acceptedRegionFindCount: $0.acceptedRegionFindCount,
                    competitiveFirstPlaceFinishes: $0.competitiveFirstPlaceFinishes,
                    everCompetitiveFirstPlace: $0.everCompetitiveFirstPlace,
                    hasPendingLocalProgression: $0.hasPendingLocalProgression
                )
            },
            sessionContext: sessionContext.map { ctx in
                Payload.SessionContextPayload(
                    sessionId: ctx.sessionId.uuidString,
                    gameInstanceId: ctx.gameInstanceId.uuidString,
                    sessionProgressionPending: pendingPayload(ctx.sessionProgressionPending),
                    sessionLedgerNetXp: ctx.sessionLedgerNetXp,
                    gameLedgerNetXp: ctx.gameLedgerNetXp
                )
            },
            ledgerSummary: ledgerSummary(for: allLedger),
            ledgerEvents: allLedger.map { ledgerRow($0, iso: iso) }
        )
    }

    @MainActor
    static func buildJSON(
        userId: String,
        sessionContext: SessionContext? = nil
    ) throws -> String {
        let payload = try buildPayload(userId: userId, sessionContext: sessionContext)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        guard let text = String(data: data, encoding: .utf8) else {
            throw ExportError.encodingFailed
        }
        return text
    }

    @MainActor
    static func resolvedUserId(from authService: FirebaseAuthService) -> String {
        authService.currentUser?.firebaseUID ?? authService.currentUser?.id ?? ""
    }

    @MainActor
    static func resolvedUserIdFromProgressionRepository() -> String {
        UserProgressionRepository.shared.currentObservedUserId ?? ""
    }

    // MARK: - Private

    enum ExportError: LocalizedError {
        case missingUserId
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .missingUserId: return "No signed-in user id for XP export."
            case .encodingFailed: return "Could not encode XP debug JSON."
            }
        }
    }

    private static func pendingPayload(_ pending: ProgressionPendingDelta) -> Payload.PendingDeltaPayload {
        Payload.PendingDeltaPayload(
            totalXp: pending.totalXp,
            acceptedRegionFindCount: pending.acceptedRegionFindCount,
            competitiveFirstPlaceFinishes: pending.competitiveFirstPlaceFinishes,
            everCompetitiveFirstPlace: pending.everCompetitiveFirstPlace
        )
    }

    private static func ledgerSummary(for events: [XpLedgerEvent]) -> Payload.LedgerSummary {
        let provisional = events.filter { $0.status == .provisional }.reduce(0) { $0 + $1.xpDelta }
        let finalStatus = events.filter { $0.status == .final }.reduce(0) { $0 + $1.xpDelta }
        return Payload.LedgerSummary(
            eventCount: events.count,
            netXpAllRows: events.reduce(0) { $0 + $1.xpDelta },
            provisionalSum: provisional,
            finalStatusSum: finalStatus
        )
    }

    private static func ledgerRow(_ event: XpLedgerEvent, iso: ISO8601DateFormatter) -> Payload.LedgerRow {
        Payload.LedgerRow(
            id: event.id,
            sessionId: event.sessionId.uuidString,
            gameInstanceId: event.gameInstanceId.uuidString,
            sourceEventId: event.sourceEventId,
            sourceEventType: event.sourceEventType,
            itemId: event.itemId,
            grantKind: event.grantKind.rawValue,
            status: event.status.rawValue,
            xpDelta: event.xpDelta,
            reasonCode: event.reasonCode.rawValue,
            xpUniquenessKey: event.xpUniquenessKey,
            createdAt: iso.string(from: event.createdAt),
            resolvedAt: event.resolvedAt.map { iso.string(from: $0) },
            metadata: event.metadata
        )
    }
}

#endif
