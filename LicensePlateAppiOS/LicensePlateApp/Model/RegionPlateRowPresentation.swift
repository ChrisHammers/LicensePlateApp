//
//  RegionPlateRowPresentation.swift
//  LicensePlateApp
//
//  Pre-built strings for license plate list rows — built in ViewModel from `DiscoveryUiProjection`.
//

import Foundation

struct FinderAvatarPresentation: Equatable, Sendable, Identifiable {
    var id: String { participantId }
    var participantId: String
    var displayName: String
    var avatarId: String?
    var legacyFallbackImageName: String?
    var foundAt: Date
}

struct RegionPlateRowPresentation: Equatable, Sendable {
    var regionId: String
    /// True when the tile should show the found treatment (projection or fallback).
    var isVisuallyFound: Bool
    var showPendingBadge: Bool
    /// Short line under region name (e.g. pending / resolved copy).
    var detailLine: String?
    /// Capsule text such as "+10 XP pending" or "+4 XP".
    var xpPillText: String?
    /// Ordered by discovery time ascending (first finder first).
    var orderedFinders: [FinderAvatarPresentation]
    /// Accessibility-ready line describing finder order.
    var findersAccessibilityValue: String?
    var accessibilityLabel: String
    var accessibilityValue: String
}

enum RegionPlateRowPresentationBuilder {

    static func build(
        regionId: String,
        regionName: String,
        projection: DiscoveryUiProjection?,
        foundFallback: Bool,
        orderedFinders: [FinderAvatarPresentation] = [],
        findersAccessibilityValue: String? = nil
    ) -> RegionPlateRowPresentation {
        let isFound = projection.map { $0.displayState == .foundVisuallyActive } ?? foundFallback
        let pending = projection.map { $0.xpPhase == .provisional || $0.syncState == .localOnly } ?? false
        let showBadge = pending && isFound

        let detailLine: String?
        let pill: String?
        if let p = projection, isFound {
            switch p.xpPhase {
            case .provisional:
                detailLine = "xp.row.detail.pending_resolution".localized
                pill = "xp.row.pill.pending".localized(p.xpShownDelta)
            case .final, .finalPending:
                if let badge = p.statusBadgeText, !badge.isEmpty {
                    detailLine = badge
                } else if p.xpShownDelta != 0 {
                    detailLine = "xp.row.detail.final_award".localized(p.xpShownDelta)
                } else {
                    detailLine = nil
                }
                pill = p.xpShownDelta != 0 ? "xp.row.pill.final".localized(p.xpShownDelta) : nil
            case .none:
                detailLine = nil
                pill = nil
            }
        } else {
            detailLine = nil
            pill = nil
        }

        let a11yLabel = regionName
        var valueParts: [String] = [isFound ? "Found".localized : "Not found".localized]
        if showBadge { valueParts.append("xp.row.a11y.pending_competitive".localized) }
        if let d = detailLine { valueParts.append(d) }
        if let pill { valueParts.append(pill) }
        if let findersAccessibilityValue, !findersAccessibilityValue.isEmpty {
            valueParts.append(findersAccessibilityValue)
        }

        return RegionPlateRowPresentation(
            regionId: regionId,
            isVisuallyFound: isFound,
            showPendingBadge: showBadge,
            detailLine: detailLine,
            xpPillText: pill,
            orderedFinders: orderedFinders,
            findersAccessibilityValue: findersAccessibilityValue,
            accessibilityLabel: a11yLabel,
            accessibilityValue: valueParts.joined(separator: ", ")
        )
    }
}
