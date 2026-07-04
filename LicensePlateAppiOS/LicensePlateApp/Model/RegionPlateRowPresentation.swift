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
    /// Short line under region name (e.g. pending or fairness status copy).
    var detailLine: String?
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
        if let p = projection, isFound {
            switch p.xpPhase {
            case .provisional:
                detailLine = "xp.row.detail.pending_resolution".localized
            case .final, .finalPending:
                if let badge = p.statusBadgeText, !badge.isEmpty {
                    detailLine = badge
                } else {
                    detailLine = nil
                }
            case .none:
                detailLine = nil
            }
        } else {
            detailLine = nil
        }

        let a11yLabel = regionName
        var valueParts: [String] = [isFound ? "Found".localized : "Not found".localized]
        if showBadge { valueParts.append("xp.row.a11y.pending_competitive".localized) }
        if let d = detailLine { valueParts.append(d) }
        if let findersAccessibilityValue, !findersAccessibilityValue.isEmpty {
            valueParts.append(findersAccessibilityValue)
        }

        return RegionPlateRowPresentation(
            regionId: regionId,
            isVisuallyFound: isFound,
            showPendingBadge: showBadge,
            detailLine: detailLine,
            orderedFinders: orderedFinders,
            findersAccessibilityValue: findersAccessibilityValue,
            accessibilityLabel: a11yLabel,
            accessibilityValue: valueParts.joined(separator: ", ")
        )
    }
}
