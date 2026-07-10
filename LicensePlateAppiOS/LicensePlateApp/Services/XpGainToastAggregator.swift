//
//  XpGainToastAggregator.swift
//  LicensePlateApp
//
//  Collapses burst ingest events into one summarized line per catalog group.
//

import Foundation

struct XpGainToastLine: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var subtitle: String?
    var xpAmount: Int
}

struct XpGainToastPresentation: Equatable {
    var totalXp: Int
    var lines: [XpGainToastLine]
    var rankBand: XpGainToastRankBand?
    var expiresAt: Date
    var dismissDuration: TimeInterval
}

enum XpGainToastAggregator {

    static func aggregate(
        events: [XpGainToastIngestEvent],
        catalog: ProgressionCatalog,
        dismissDuration: TimeInterval,
        now: Date = .now
    ) -> XpGainToastPresentation {
        let totalXp = events.reduce(0) { $0 + $1.xpAmount }
        var byGroup: [String: [XpGainToastIngestEvent]] = [:]
        for event in events {
            byGroup[event.groupId, default: []].append(event)
        }

        let lines: [XpGainToastLine] = catalog.sortedXpToastGroups.compactMap { group in
            guard let groupEvents = byGroup[group.id], !groupEvents.isEmpty else { return nil }
            let title = title(for: group, events: groupEvents)
            guard !title.isEmpty else { return nil }
            let subtitle = subtitle(for: group, events: groupEvents)
            let xpAmount = groupEvents.reduce(0) { $0 + $1.xpAmount }
            return XpGainToastLine(id: group.id, title: title, subtitle: subtitle, xpAmount: xpAmount)
        }

        return XpGainToastPresentation(
            totalXp: totalXp,
            lines: lines,
            expiresAt: now.addingTimeInterval(dismissDuration),
            dismissDuration: dismissDuration
        )
    }

    // MARK: - Copy

    private static func title(
        for group: ProgressionCatalogXpToastGroup,
        events: [XpGainToastIngestEvent]
    ) -> String {
        switch group.id {
        case "discovery":
            return discoveryTitle(for: group, events: events)
        case "return_streak":
            return streakTitle(for: group, events: events)
        default:
            return countTitle(for: group, count: events.count)
        }
    }

    private static func discoveryTitle(
        for group: ProgressionCatalogXpToastGroup,
        events: [XpGainToastIngestEvent]
    ) -> String {
        let sorted = events.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.sourceId < $1.sourceId
        }
        var seen = Set<String>()
        var regions: [String] = []
        for event in sorted {
            guard let token = event.displayToken, !token.isEmpty else { continue }
            if seen.insert(token).inserted {
                regions.append(token)
            }
        }
        switch regions.count {
        case 0:
            return group.titleKeySingle.localized
        case 1:
            return group.titleKeySingle.localized(regions[0])
        case 2:
            return "xp.toast.group.discovery.double".localized(regions[0], regions[1])
        default:
            return group.titleKeyMulti.localized(regions[0], regions.count - 1)
        }
    }

    private static func streakTitle(
        for group: ProgressionCatalogXpToastGroup,
        events: [XpGainToastIngestEvent]
    ) -> String {
        let latest = events.max {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.sourceId < $1.sourceId
        }
        let streakDays = Int(latest?.displayToken ?? "") ?? events.count
        if streakDays <= 1 {
            return group.titleKeySingle.localized(streakDays)
        }
        return group.titleKeyMulti.localized(streakDays)
    }

    private static func countTitle(for group: ProgressionCatalogXpToastGroup, count: Int) -> String {
        if count <= 1 {
            return group.titleKeySingle.localized(count)
        }
        return group.titleKeyMulti.localized(count)
    }

    private static func subtitle(
        for group: ProgressionCatalogXpToastGroup,
        events: [XpGainToastIngestEvent]
    ) -> String? {
        guard group.id == "discovery", events.contains(where: \.isProvisionalDiscovery) else { return nil }
        return group.detailKey?.localized
    }
}
