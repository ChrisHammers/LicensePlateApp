//
//  DiscoveryUiProjectionBuilder.swift
//  LicensePlateApp
//
//  Stable discovery + XP read model for one item and viewer.
//

import Foundation

enum DiscoveryUiProjectionBuilder {

    static func project(
        sessionId: UUID,
        gameInstanceId: UUID,
        itemId: String,
        viewerUserId: String,
        gameMode: GameMode,
        discoveriesForItem: [GameDiscovery],
        resolution: DiscoveryResolution?,
        ledgerEventsForItem: [XpLedgerEvent],
        lastUpdated: Date = .now
    ) -> DiscoveryUiProjection {
        let summary = ParticipantDiscoveryResolver.summary(discoveries: discoveriesForItem, gameMode: gameMode)
        let mine = discoveriesForItem.filter { $0.participantId == viewerUserId }
        let viewerHasActive = !mine.isEmpty

        let displayState: DiscoveryTileDisplayState = viewerHasActive ? .foundVisuallyActive : .notFound

        let netLedger = ledgerEventsForItem.reduce(0) { $0 + $1.xpDelta }
        let hasProvisional = ledgerEventsForItem.contains { $0.status == .provisional }
        let xpPhase: DiscoveryXpProjectionPhase
        if netLedger == 0 && !hasProvisional {
            xpPhase = .none
        } else if hasProvisional && (resolution == nil || resolution?.finalOutcome == .pending) {
            xpPhase = .provisional
        } else {
            xpPhase = .final
        }

        let syncState: DiscoverySyncProjectionState
        if let r = resolution?.finalOutcome, r != .pending {
            syncState = .synced
        } else if hasProvisional {
            syncState = .localOnly
        } else {
            syncState = .synced
        }

        let badge: String?
        if let r = resolution?.finalOutcome, r != .pending, gameMode == .competitive {
            badge = badgeText(for: r, summary: summary, viewerUserId: viewerUserId)
        } else {
            badge = nil
        }

        return DiscoveryUiProjection(
            sessionId: sessionId,
            gameInstanceId: gameInstanceId,
            itemId: itemId,
            viewerUserId: viewerUserId,
            displayState: displayState,
            tripAttribution: summary,
            viewerHasActiveDiscovery: viewerHasActive,
            xpPhase: xpPhase,
            xpShownDelta: netLedger,
            syncState: syncState,
            statusBadgeText: badge,
            lastUpdated: lastUpdated
        )
    }

    private static func badgeText(
        for outcome: DiscoveryResolutionOutcome,
        summary: ParticipantDiscoverySummary,
        viewerUserId: String
    ) -> String? {
        switch outcome {
        case .acceptedFirst:
            if summary.firstFinderParticipantId == viewerUserId {
                return "First finder".localized
            }
            return nil
        case .acceptedLate:
            return "Late find +4 XP".localized
        case .rejectedDuplicate, .rejectedPersonalDuplicate, .rejectedRisk, .rejectedInvalidState:
            return "No trip XP".localized
        default:
            return nil
        }
    }
}
