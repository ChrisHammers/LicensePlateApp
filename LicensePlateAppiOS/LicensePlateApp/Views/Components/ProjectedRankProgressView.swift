//
//  ProjectedRankProgressView.swift
//  LicensePlateApp
//
//  Visual-only: server XP fill + optional pending overlay (does not grant unlocks).
//

import SwiftUI

struct ProjectedRankProgressView: View {
    let serverXp: Int
    let pendingLedgerXp: Int

    private let primaryBarHeight: CGFloat = 8
    private let nextBandBarHeight: CGFloat = 5
    private let barCornerRadius: CGFloat = 4

    private var fill: ProjectedBandFill {
        ProgressionRankBands.projectedBandFill(
            serverXp: max(0, serverXp),
            pendingXp: max(0, pendingLedgerXp)
        )
    }

    var body: some View {
        let bandFill = fill
        VStack(alignment: .leading, spacing: 8) {
            Text("profile.xp.rank_band_title".localized)
                .font(.system(.caption, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(Color.Theme.primaryBlue)
                .accessibilityAddTraits(.isHeader)

            composedBar(
                syncedFraction: bandFill.syncedFractionInCurrentBand,
                pendingFraction: bandFill.pendingFractionInCurrentBand,
                height: primaryBarHeight
            )

            if bandFill.showsNextBandBar {
                composedBar(
                    syncedFraction: 0,
                    pendingFraction: bandFill.pendingFractionInNextBand,
                    height: nextBandBarHeight
                )
                .accessibilityLabel("profile.xp.pending_next_band_caption".localized)
            }

            if pendingLedgerXp > 0 {
                Text("profile.xp.pending_overlay_caption".localized)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)

                if bandFill.showsBeyondNextBandCaption {
                    Text("profile.xp.pending_beyond_next_band_caption".localized)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                } else if bandFill.showsNextBandBar {
                    Text("profile.xp.pending_next_band_caption".localized)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("profile.xp.rank_band.a11y".localized)
        .accessibilityValue("profile.xp.rank_band.a11y.value".localized(serverXp, pendingLedgerXp))
    }

    private func composedBar(
        syncedFraction: Double,
        pendingFraction: Double,
        height: CGFloat
    ) -> some View {
        GeometryReader { geo in
            let width = geo.size.width
            let syncedWidth = width * min(1, max(0, syncedFraction))
            let pendingWidth = width * min(1 - min(1, max(0, syncedFraction)), max(0, pendingFraction))
            let r = barCornerRadius

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: r, style: .continuous)
                    .fill(Color.Theme.softBrown.opacity(0.15))

                HStack(spacing: 0) {
                    if syncedWidth > 0 {
                        UnevenRoundedRectangle(
                            topLeadingRadius: r,
                            bottomLeadingRadius: r,
                            bottomTrailingRadius: pendingWidth > 0 ? 0 : r,
                            topTrailingRadius: pendingWidth > 0 ? 0 : r,
                            style: .continuous
                        )
                        .fill(Color.Theme.primaryBlue)
                        .frame(width: syncedWidth)
                    }
                    if pendingWidth > 0 {
                        UnevenRoundedRectangle(
                            topLeadingRadius: syncedWidth > 0 ? 0 : r,
                            bottomLeadingRadius: syncedWidth > 0 ? 0 : r,
                            bottomTrailingRadius: r,
                            topTrailingRadius: r,
                            style: .continuous
                        )
                        .fill(Color.Theme.accentYellow.opacity(0.85))
                        .frame(width: pendingWidth)
                    }
                }
            }
        }
        .frame(height: height)
    }
}

#Preview("No pending") {
    ProjectedRankProgressView(serverXp: 37, pendingLedgerXp: 0)
        .padding()
}

#Preview("Fits in current band") {
    ProjectedRankProgressView(serverXp: 37, pendingLedgerXp: 10)
        .padding()
}

#Preview("Spills into next band only") {
    // Band size 100: room in band at 80 synced = 20; pending 50 → 20 in current, 30 in next, 0 beyond.
    ProjectedRankProgressView(serverXp: 80, pendingLedgerXp: 50)
        .padding()
}

#Preview("Goes past next band") {
    // Screenshot-like: band 100, 320 synced (20 in band), +390 pending → fills current, full next, 210 beyond.
    ProjectedRankProgressView(serverXp: 320, pendingLedgerXp: 390)
        .padding()
}
