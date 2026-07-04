//
//  XpGainToastLineBuilder.swift
//  LicensePlateApp
//
//  Maps ledger rows and remote XP grants to toast line copy.
//

import Foundation

struct XpGainToastLine: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var subtitle: String?
    var xpDisplayText: String
}

enum XpGainToastEligibility {

    static func shouldToastLedgerRow(_ row: XpLedgerEvent) -> Bool {
        row.xpDelta > 0 && row.grantKind != .milestoneUnlock
    }

    static func shouldToastRemoteGrant(_ grant: UserXpGrant) -> Bool {
        guard grant.amount > 0 else { return false }
        if grant.achievementId != nil { return false }
        if grant.reason == UserXpGrantReason.achievementUnlock.rawValue { return false }
        if grant.reason == UserXpGrantReason.regionFoundBaseDiscovery.rawValue { return false }
        return true
    }
}

enum XpGainToastLineBuilder {

    private static func regionTitle(for itemId: String) -> String {
        PlateRegion.all.first { $0.id == itemId }?.name ?? itemId
    }

    static func line(from ledgerRow: XpLedgerEvent) -> XpGainToastLine? {
        guard XpGainToastEligibility.shouldToastLedgerRow(ledgerRow) else { return nil }
        guard let feed = XpFeedProjectionBuilder.lines(from: [ledgerRow], itemTitle: regionTitle(for:)).first else {
            return nil
        }
        return XpGainToastLine(
            id: "ledger|\(ledgerRow.id)",
            title: feed.title,
            subtitle: feed.subtitle,
            xpDisplayText: feed.xpDisplayText
        )
    }

    static func line(from grant: UserXpGrant) -> XpGainToastLine? {
        guard XpGainToastEligibility.shouldToastRemoteGrant(grant) else { return nil }
        let (title, subtitle): (String, String?)
        switch grant.reason {
        case UserXpGrantReason.competitiveFirstPlaceFinish.rawValue:
            title = "xp.toast.grant.competitive_win.title".localized
            subtitle = "xp.toast.grant.competitive_win.subtitle".localized
        case UserXpGrantReason.legacyUnledgeredBalance.rawValue:
            title = "xp.toast.grant.legacy_balance.title".localized
            subtitle = nil
        default:
            title = "xp.toast.grant.generic.title".localized
            subtitle = nil
        }
        return XpGainToastLine(
            id: "grant|\(grant.grantId)",
            title: title,
            subtitle: subtitle,
            xpDisplayText: "xp.toast.grant.xp_format".localized(grant.amount)
        )
    }
}
