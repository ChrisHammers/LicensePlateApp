//
//  XpFeedProjectionBuilder.swift
//  LicensePlateApp
//
//  Feed/snackbar lines from ledger rows.
//

import Foundation

enum XpFeedProjectionBuilder {

    /// Maps ledger rows to feed lines sorted by `createdAt`.
    static func lines(
        from ledgerEvents: [XpLedgerEvent],
        itemTitle: (String) -> String
    ) -> [XpFeedProjection] {
        let sorted = ledgerEvents.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id < $1.id
        }
        return sorted.compactMap { row in
            line(from: row, itemTitle: itemTitle)
        }
    }

    private static func line(from row: XpLedgerEvent, itemTitle: (String) -> String) -> XpFeedProjection? {
        guard row.status != .voided else { return nil }
        // Settlement markers with no XP change are not shown in the trip recap feed.
        if row.grantKind == .reconciliationAdjustment, row.xpDelta == 0 { return nil }

        let name = itemTitle(row.itemId)
        let state: XpFeedLineState = row.status == .provisional ? .provisional : .final
        let (title, subtitle, xpText): (String, String?, String)
        switch row.grantKind {
        case .provisionalDiscoveryXp:
            title = "%@ found".localized(name)
            subtitle = "Pending resolution".localized
            xpText = "+%d XP pending".localized(row.xpDelta)
        case .reconciliationAdjustment:
            title = row.xpDelta < 0
                ? "reward.popup.kicker.xp_removed".localized
                : "%@ resolved".localized(name)
            subtitle = row.xpDelta < 0
                ? "reward.popup.xp_removed.detail".localized
                : row.reasonCode.rawValue.replacingOccurrences(of: "_", with: " ")
            xpText = row.xpDelta >= 0
                ? "+%d XP".localized(row.xpDelta)
                : "%d XP".localized(row.xpDelta)
        case .finalDiscoveryAward:
            title = "%@ found".localized(name)
            subtitle = nil
            xpText = "+%d XP".localized(row.xpDelta)
        case .tripCompletion:
            // Completion bonuses are scoped to the trip/game, not a region — title by reason,
            // reusing the XP toast group copy so offline recap lines read the same as online ones.
            title = completionTitle(for: row.reasonCode)
            subtitle = nil
            xpText = row.status == .provisional
                ? "+%d XP pending".localized(row.xpDelta)
                : "+%d XP".localized(row.xpDelta)
        default:
            title = name
            subtitle = row.grantKind.rawValue
            xpText = "%d XP".localized(row.xpDelta)
        }
        return XpFeedProjection(
            id: row.id,
            sourceEventId: row.sourceEventId,
            itemId: row.itemId,
            title: title,
            subtitle: subtitle,
            xpDisplayText: xpText,
            state: state,
            createdAt: row.createdAt
        )
    }

    /// Existing localized XP toast group titles (en / es-419 / fr-CA already shipped).
    private static func completionTitle(for reason: XpReasonCode) -> String {
        switch reason {
        case .gameEnded: return "xp.toast.group.game_ended.single".localized
        case .gameFullClear: return "xp.toast.group.game_full_clear.single".localized
        case .tripEnded: return "xp.toast.group.trip_ended.single".localized
        case .tripParticipation: return "xp.toast.group.trip_participation.single".localized
        case .tripCompetitiveFirstPlace: return "xp.toast.group.trip_competitive_first.single".localized
        case .competitiveFirstPlaceFinish, .competitiveSecondPlace, .competitiveThirdPlace:
            return "xp.toast.group.competitive_place.single".localized
        default: return "xp.toast.group.other.single".localized
        }
    }
}
