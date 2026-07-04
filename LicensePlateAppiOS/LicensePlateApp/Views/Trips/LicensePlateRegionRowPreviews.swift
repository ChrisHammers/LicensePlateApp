//
//  LicensePlateRegionRowPreviews.swift
//  LicensePlateApp
//
//  Focused row previews kept out of `LicensePlateGameView.swift` so the canvas
//  can render row states without timing out on the full game screen file.
//

import Foundation
import SwiftUI

#Preview("Region row states") {
    LicensePlateRowStatesPreview()
}

#Preview("Region row states - Dark") {
    LicensePlateRowStatesPreview()
        .preferredColorScheme(.dark)
}

#Preview("Region row states - Dynamic Type") {
    LicensePlateRowStatesPreview()
        .dynamicTypeSize(.accessibility3)
}

private struct LicensePlateRowStatesPreview: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                rowCard(
                    title: "Not found",
                    presentation: LicensePlateRowPreviewData.notFound
                )
                rowCard(
                    title: "Found (plain)",
                    presentation: LicensePlateRowPreviewData.foundPlain
                )
                rowCard(
                    title: "Pending resolution",
                    presentation: LicensePlateRowPreviewData.pendingResolution
                )
                rowCard(
                    title: "Status badge: First finder",
                    presentation: LicensePlateRowPreviewData.firstFinder
                )
                rowCard(
                    title: "Status badge: Accepted late",
                    presentation: LicensePlateRowPreviewData.acceptedLate
                )
                rowCard(
                    title: "Status badge: Adjusted after sync",
                    presentation: LicensePlateRowPreviewData.adjustedAfterSync
                )
                rowCard(
                    title: "Disabled row",
                    presentation: LicensePlateRowPreviewData.notFound,
                    isDisabled: true
                )
            }
            .padding()
        }
        .background(Color.Theme.background)
    }

    @ViewBuilder
    private func rowCard(
        title: String,
        presentation: RegionPlateRowPresentation,
        isDisabled: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Color.Theme.primaryBlue)
            RegionCellView(
                region: LicensePlateRowPreviewData.texas,
                presentation: presentation,
                isSelectedFallback: false,
                toggleAction: {},
                isDisabled: isDisabled
            )
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.Theme.cardBackground)
            )
        }
    }
}

private enum LicensePlateRowPreviewData {
    static let texas = PlateRegion.all.first { $0.id == "us-tx" } ?? PlateRegion.all[0]

    static let notFound = makePresentation(
        isVisuallyFound: false
    )

    static let foundPlain = makePresentation(
        isVisuallyFound: true,
        orderedFinders: [finderAlex],
        findersAccessibilityValue: "Alex found this region first."
    )

    static let pendingResolution = makePresentation(
        isVisuallyFound: true,
        showPendingBadge: true,
        detailLine: "xp.row.detail.pending_resolution".localized,
        detailStyle: .pending,
        orderedFinders: [finderAlex],
        findersAccessibilityValue: "Alex found this region first."
    )

    static let firstFinder = makePresentation(
        isVisuallyFound: true,
        detailLine: "First finder".localized,
        detailStyle: .firstFinder,
        orderedFinders: [finderAlex],
        findersAccessibilityValue: "Alex found this region first."
    )

    static let acceptedLate = makePresentation(
        isVisuallyFound: true,
        detailLine: "xp.discovery.badge.accepted_late".localized,
        detailStyle: .acceptedLate,
        orderedFinders: [finderMorgan, finderAlex],
        findersAccessibilityValue: "Morgan found this region first. Alex found it second."
    )

    static let adjustedAfterSync = makePresentation(
        isVisuallyFound: true,
        detailLine: "xp.discovery.badge.adjusted_after_sync".localized,
        detailStyle: .adjustedAfterSync,
        orderedFinders: [finderMorgan, finderAlex, finderJordan],
        findersAccessibilityValue: "Morgan found this region first. Alex found it second. Jordan found it third."
    )

    private static let finderAlex = FinderAvatarPresentation(
        participantId: "user-alex",
        displayName: "Alex",
        avatarId: "navigator_raccoon",
        legacyFallbackImageName: nil,
        foundAt: Date(timeIntervalSince1970: 100)
    )

    private static let finderMorgan = FinderAvatarPresentation(
        participantId: "user-morgan",
        displayName: "Morgan",
        avatarId: "scout_otter",
        legacyFallbackImageName: nil,
        foundAt: Date(timeIntervalSince1970: 90)
    )

    private static let finderJordan = FinderAvatarPresentation(
        participantId: "user-jordan",
        displayName: "Jordan",
        avatarId: nil,
        legacyFallbackImageName: "dog_blue",
        foundAt: Date(timeIntervalSince1970: 110)
    )

    private static func makePresentation(
        isVisuallyFound: Bool,
        showPendingBadge: Bool = false,
        detailLine: String? = nil,
        detailStyle: RegionPlateRowStatusStyle? = nil,
        orderedFinders: [FinderAvatarPresentation] = [],
        findersAccessibilityValue: String? = nil
    ) -> RegionPlateRowPresentation {
        var valueParts: [String] = [isVisuallyFound ? "Found".localized : "Not found".localized]
        if showPendingBadge {
            valueParts.append("xp.row.a11y.pending_competitive".localized)
        }
        if let detailLine, !detailLine.isEmpty {
            valueParts.append(detailLine)
        }
        if let findersAccessibilityValue, !findersAccessibilityValue.isEmpty {
            valueParts.append(findersAccessibilityValue)
        }

        return RegionPlateRowPresentation(
            regionId: texas.id,
            isVisuallyFound: isVisuallyFound,
            showPendingBadge: showPendingBadge,
            detailLine: detailLine,
            detailStyle: detailStyle,
            orderedFinders: orderedFinders,
            findersAccessibilityValue: findersAccessibilityValue,
            accessibilityLabel: texas.name,
            accessibilityValue: valueParts.joined(separator: ", ")
        )
    }
}
