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

    private var serverBandProgress: Double {
        ProgressionRankBands.progressInCurrentBand(totalXp: max(0, serverXp))
    }

    private var pendingOverlayProgress: Double {
        guard pendingLedgerXp > 0 else { return 0 }
        return ProgressionRankBands.pendingOverlayFraction(pendingXp: pendingLedgerXp)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("profile.xp.rank_band_title".localized)
                .font(.system(.caption, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(Color.Theme.primaryBlue)
                .accessibilityAddTraits(.isHeader)
            ProgressView(value: serverBandProgress, total: 1.0)
                .progressViewStyle(.linear)
                .tint(Color.Theme.primaryBlue)
            if pendingLedgerXp > 0 {
                ProgressView(value: pendingOverlayProgress, total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(Color.Theme.accentYellow.opacity(0.85))
                Text("profile.xp.pending_overlay_caption".localized)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("profile.xp.rank_band.a11y".localized)
        .accessibilityValue("profile.xp.rank_band.a11y.value".localized(serverXp, pendingLedgerXp))
    }
}

#Preview {
    ProjectedRankProgressView(serverXp: 37, pendingLedgerXp: 10)
        .padding()
}
