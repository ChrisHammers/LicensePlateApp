//
//  ProjectedRankProgressView.swift
//  LicensePlateApp
//
//  Visual-only: server XP fill + optional pending overlay (does not grant unlocks).
//  Fill uses RankLadder segments (same math as XP gain toast).
//

import SwiftUI

struct ProjectedRankProgressView: View {
    let serverXp: Int
    let pendingLedgerXp: Int

    private let primaryBarHeight: CGFloat = 8
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
                } else if bandFill.showsNextRankCaption {
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

#Preview("Fits in current rank") {
    // Early rank span 1000: 50 pending ≈ 5% yellow
    ProjectedRankProgressView(serverXp: 0, pendingLedgerXp: 50)
        .padding()
}

#Preview("Crosses into next rank") {
    // 900 + 150 → after at 1050 in 1000…3000 segment
    ProjectedRankProgressView(serverXp: 900, pendingLedgerXp: 150)
        .padding()
}

#Preview("Goes past next rank") {
    // 0 + 3500 → past 3000 threshold into third rank
    ProjectedRankProgressView(serverXp: 0, pendingLedgerXp: 3500)
        .padding()
}
