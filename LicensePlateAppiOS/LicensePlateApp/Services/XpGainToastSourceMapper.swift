//
//  XpGainToastSourceMapper.swift
//  LicensePlateApp
//
//  Maps ledger rows and remote XP grants to catalog-grouped ingest events.
//

import Foundation

struct XpGainToastIngestEvent: Equatable, Sendable {
    var sourceId: String
    var groupId: String
    var xpAmount: Int
    var displayToken: String?
    var createdAt: Date
    var isProvisionalDiscovery: Bool
}

enum XpGainToastSourceMapper {

    static func ingestEvent(from ledgerRow: XpLedgerEvent, catalog: ProgressionCatalog) -> XpGainToastIngestEvent? {
        guard XpGainToastEligibility.shouldToastLedgerRow(ledgerRow) else { return nil }
        guard let groupId = matchGroup(
            catalog: catalog,
            grantKind: ledgerRow.grantKind.rawValue,
            reasonCode: ledgerRow.reasonCode.rawValue,
            grantReason: nil
        ) else { return nil }

        let displayToken: String?
        switch groupId {
        case "discovery":
            displayToken = regionName(for: ledgerRow.itemId)
        case "return_streak":
            displayToken = ledgerRow.metadata?[XpLedgerMetadataKey.returnStreakDayCount]
                ?? ledgerRow.metadata?["return_streak_day_count"]
        case "achievement":
            displayToken = ledgerRow.itemId.isEmpty ? nil : ledgerRow.itemId
        default:
            displayToken = nil
        }

        return XpGainToastIngestEvent(
            sourceId: "ledger|\(ledgerRow.id)",
            groupId: groupId,
            xpAmount: ledgerRow.xpDelta,
            displayToken: displayToken,
            createdAt: ledgerRow.createdAt,
            isProvisionalDiscovery: groupId == "discovery" && ledgerRow.status == .provisional
        )
    }

    static func ingestEvent(from grant: UserXpGrant, catalog: ProgressionCatalog) -> XpGainToastIngestEvent? {
        guard XpGainToastEligibility.shouldToastRemoteGrant(grant) else { return nil }
        guard let groupId = matchGroup(
            catalog: catalog,
            grantKind: nil,
            reasonCode: nil,
            grantReason: grant.reason
        ) else { return nil }

        let displayToken: String? = groupId == "achievement" ? grant.achievementId : nil

        return XpGainToastIngestEvent(
            sourceId: "grant|\(grant.grantId)",
            groupId: groupId,
            xpAmount: grant.amount,
            displayToken: displayToken,
            createdAt: grant.grantedAt ?? .now,
            isProvisionalDiscovery: false
        )
    }

    // MARK: - Private

    private static func matchGroup(
        catalog: ProgressionCatalog,
        grantKind: String?,
        reasonCode: String?,
        grantReason: String?
    ) -> String? {
        let sorted = catalog.sortedXpToastGroups.filter { $0.id != "other" }
        for group in sorted {
            if matches(group: group, grantKind: grantKind, reasonCode: reasonCode, grantReason: grantReason) {
                return group.id
            }
        }
        return catalog.xpToastGroup(id: "other") != nil ? "other" : nil
    }

    private static func matches(
        group: ProgressionCatalogXpToastGroup,
        grantKind: String?,
        reasonCode: String?,
        grantReason: String?
    ) -> Bool {
        let matchers = group.matchers
        let hasLedgerMatchers = !(matchers.ledgerGrantKinds?.isEmpty ?? true)
            || !(matchers.ledgerReasonCodes?.isEmpty ?? true)
        let hasGrantMatchers = !(matchers.grantReasons?.isEmpty ?? true)

        if let grantReason {
            guard hasGrantMatchers else { return false }
            guard let reasons = matchers.grantReasons, reasons.contains(grantReason) else { return false }
            return true
        }

        guard grantKind != nil || reasonCode != nil else { return false }
        if hasGrantMatchers && !hasLedgerMatchers { return false }

        if let kinds = matchers.ledgerGrantKinds, !kinds.isEmpty {
            guard let grantKind, kinds.contains(grantKind) else { return false }
        }
        if let reasons = matchers.ledgerReasonCodes, !reasons.isEmpty {
            guard let reasonCode, reasons.contains(reasonCode) else { return false }
        }
        return hasLedgerMatchers || !hasGrantMatchers
    }

    private static func regionName(for itemId: String) -> String {
        PlateRegion.all.first { $0.id == itemId }?.name ?? itemId
    }
}
