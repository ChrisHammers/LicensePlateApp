//
//  XpGainToastBanner.swift
//  LicensePlateApp
//
//  Auto-dismissing top toast for XP gains with countdown progress bar.
//

import SwiftUI

struct XpGainToastBanner: View {
    let presentation: XpGainToastPresentation
    var onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(presentation.lines) { line in
                    lineContent(line)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, presentation.rankBand == nil ? 10 : 8)

            if let rankBand = presentation.rankBand {
                rankBandSection(rankBand)
            }

            dismissTimerBar
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.Theme.primaryBlue.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 5, x: 0, y: 2)
        .shadow(color: .black.opacity(0.28), radius: 22, x: 0, y: 12)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
        .accessibilityAction { onDismiss() }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("xp.toast.a11y.hint".localized)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func lineContent(_ line: XpGainToastLine) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(line.title)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Color.Theme.primaryBlue)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle = line.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func rankBandSection(_ band: XpGainToastRankBand) -> some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                rankBandSide(
                    icon: band.currentRankIcon,
                    rankLevel: band.currentRankLevel,
                    levelLabel: "rank.progression.rank_label".localized(band.currentRankLevel),
                    subtitle: band.currentRankTitle,
                    detail: "xp.toast.total_xp_format".localized(band.burstXpGained),
                    alignment: .leading
                )

                Spacer(minLength: 8)

                if band.isMaxRank {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("xp.toast.rank_band.max_rank".localized)
                            .font(.system(.caption2, design: .rounded).weight(.semibold))
                            .foregroundStyle(Color.Theme.softBrown)
                            .multilineTextAlignment(.trailing)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                } else if let nextLevel = band.nextRankLevel,
                          let nextTitle = band.nextRankTitle,
                          let nextIcon = band.nextRankIcon {
                    rankBandSide(
                        icon: nextIcon,
                        rankLevel: nextLevel,
                        levelLabel: "rank.progression.rank_label".localized(nextLevel),
                        subtitle: nextTitle,
                        detail: "rank.progression.xp_to_next".localized(
                            (band.xpToNextRank ?? 0).formatted(),
                            nextTitle
                        ),
                        alignment: .trailing
                    )
                }
            }

            rankProgressBar(band)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.Theme.primaryBlue.opacity(0.05))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("xp.toast.rank_band.a11y".localized)
    }

    private func rankBandSide(
        icon: String,
        rankLevel: Int,
        levelLabel: String,
        subtitle: String? = nil,
        detail: String,
        alignment: HorizontalAlignment
    ) -> some View {
        HStack(spacing: 8) {
            if alignment == .trailing {
                sideText(levelLabel: levelLabel, subtitle: subtitle, detail: detail, alignment: alignment)
                rankIconBadge(systemName: icon, rankLevel: rankLevel)
            } else {
                rankIconBadge(systemName: icon, rankLevel: rankLevel)
                sideText(levelLabel: levelLabel, subtitle: subtitle, detail: detail, alignment: alignment)
            }
        }
    }

    private func sideText(
        levelLabel: String,
        subtitle: String?,
        detail: String,
        alignment: HorizontalAlignment
    ) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(levelLabel)
                .font(.system(.caption2, design: .rounded).weight(.heavy))
                .foregroundStyle(Color.Theme.primaryBlue)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.Theme.softBrown)
                    .lineLimit(1)
            }
            Text(detail)
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(Color.Theme.softBrown)
                .multilineTextAlignment(alignment == .trailing ? .trailing : .leading)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
    }

    private func rankIconBadge(systemName: String, rankLevel: Int) -> some View {
        let accent = Rank(level: rankLevel, title: "", xpRequired: 0, unlocks: []).accent
        return Image(systemName: systemName)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(accent, in: Circle())
            .accessibilityHidden(true)
    }

    private func rankProgressBar(_ band: XpGainToastRankBand) -> some View {
        GeometryReader { geo in
            let width = geo.size.width
            let primaryWidth = width * band.progressBeforeBurst
            let gainWidth = width * max(0, band.progressAfterBurst - band.progressBeforeBurst)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.Theme.softBrown.opacity(0.15))
                Capsule()
                    .fill(Color.Theme.primaryBlue)
                    .frame(width: primaryWidth)
                Capsule()
                    .fill(Color.Theme.accentYellow)
                    .frame(width: gainWidth)
                    .offset(x: primaryWidth)
            }
        }
        .frame(height: 8)
        .accessibilityLabel("xp.toast.rank_band.progress.a11y".localized)
        .accessibilityValue(
            "xp.toast.rank_band.progress.a11y.value".localized(
                Int(band.progressBeforeBurst * 100),
                Int(max(0, band.progressAfterBurst - band.progressBeforeBurst) * 100)
            )
        )
    }

    @ViewBuilder
    private var dismissTimerBar: some View {
        if reduceMotion {
            Rectangle()
                .fill(Color.Theme.primaryBlue)
                .frame(height: 3)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let remaining = max(0, presentation.expiresAt.timeIntervalSince(context.date))
                let fraction = min(1, max(0, remaining / presentation.dismissDuration))
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.Theme.cardBackground)
                        Rectangle()
                            .fill(Color.Theme.primaryBlue)
                            .frame(width: geo.size.width * fraction)
                    }
                }
                .frame(height: 3)
            }
        }
    }

    private var accessibilityLabel: String {
        var parts: [String] = []
        if let band = presentation.rankBand {
            parts.append("xp.toast.total_xp_format".localized(band.burstXpGained))
            parts.append("rank.progression.rank_label".localized(band.currentRankLevel))
            if band.isMaxRank {
                parts.append("xp.toast.rank_band.max_rank".localized)
            } else if let nextTitle = band.nextRankTitle, let xpToNext = band.xpToNextRank {
                parts.append("rank.progression.xp_to_next".localized(xpToNext.formatted(), nextTitle))
            }
        } else {
            parts.append("xp.toast.total_xp_format".localized(presentation.totalXp))
        }
        parts.append(contentsOf: presentation.lines.map { line in
            if let subtitle = line.subtitle, !subtitle.isEmpty {
                return "\(line.title), \(subtitle)"
            }
            return line.title
        })
        return "xp.toast.a11y.label".localized(parts.joined(separator: "; "))
    }
}

#Preview("Aggregated burst with rank band") {
    XpGainToastBanner(
        presentation: XpGainToastPresentation(
            totalXp: 24,
            lines: [
                XpGainToastLine(
                    id: "discovery",
                    title: "Discovered Texas and 2 others",
                    subtitle: nil
                ),
                XpGainToastLine(
                    id: "return_streak",
                    title: "2 day streak",
                    subtitle: nil
                )
            ],
            rankBand: XpGainToastRankBand(
                currentRankLevel: 2,
                currentRankTitle: "Road Warrior",
                currentRankIcon: "car.2.fill",
                nextRankLevel: 3,
                nextRankTitle: "Highway Hero",
                nextRankIcon: "flame.fill",
                xpToNextRank: 450,
                burstXpGained: 24,
                progressBeforeBurst: 0.35,
                progressAfterBurst: 0.52,
                isMaxRank: false
            ),
            expiresAt: Date().addingTimeInterval(4),
            dismissDuration: 4
        ),
        onDismiss: {}
    )
    .padding(.top, 8)
}

#Preview("Discovery pending") {
    XpGainToastBanner(
        presentation: XpGainToastPresentation(
            totalXp: 10,
            lines: [
                XpGainToastLine(
                    id: "discovery",
                    title: "Discovered California",
                    subtitle: "Pending resolution"
                )
            ],
            rankBand: nil,
            expiresAt: Date().addingTimeInterval(4),
            dismissDuration: 4
        ),
        onDismiss: {}
    )
    .padding(.top, 8)
}
