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

    private let rankBarHeight: CGFloat = 8
    private let rankBarCornerRadius: CGFloat = 4
    private let toastContentPadding: CGFloat = 12
    private let toastScreenInset: CGFloat = 20
    private let rankBandInnerGutter: CGFloat = 4
    private let rankSideIconSpacing: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(presentation.lines) { line in
                    lineContent(line)
                }
            }
            .padding(.horizontal, toastContentPadding)
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
        .padding(.horizontal, toastScreenInset)
        .accessibilityElement(children: .combine)
        .accessibilityAction { onDismiss() }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("xp.toast.a11y.hint".localized)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func lineContent(_ line: XpGainToastLine) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(line.title)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text("xp.toast.grant.xp_format".localized(line.xpAmount))
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(Color.Theme.softBrown)
            }
            if let subtitle = line.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func rankBandSection(_ band: XpGainToastRankBand) -> some View {
        HStack(alignment: .center, spacing: rankBandInnerGutter) {
            currentRankSide(band)
                .frame(maxWidth: .infinity, alignment: .leading)

            rankProgressBar(band)
                .frame(maxWidth: .infinity)

            nextRankSide(band)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, toastContentPadding)
        .padding(.vertical, 10)
        .background(Color.Theme.primaryBlue.opacity(0.05))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("xp.toast.rank_band.a11y".localized)
    }

    private func currentRankSide(_ band: XpGainToastRankBand) -> some View {
        HStack(alignment: .center, spacing: rankSideIconSpacing) {
            rankIconBadge(systemName: band.currentRankIcon, rankLevel: band.currentRankLevel)
            VStack(alignment: .leading, spacing: 2) {
                Text("rank.progression.rank_label".localized(band.currentRankLevel))
                    .font(.system(.caption2, design: .rounded).weight(.heavy))
                    .foregroundStyle(Color.Theme.primaryBlue)
                Text(band.currentRankTitle)
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.Theme.softBrown)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func nextRankSide(_ band: XpGainToastRankBand) -> some View {
        if band.isMaxRank {
            Text("xp.toast.rank_band.max_rank".localized)
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(Color.Theme.softBrown)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else if let nextLevel = band.nextRankLevel,
                  let nextTitle = band.nextRankTitle,
                  let nextIcon = band.nextRankIcon {
            HStack(alignment: .center, spacing: rankSideIconSpacing) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("rank.progression.rank_label".localized(nextLevel))
                        .font(.system(.caption2, design: .rounded).weight(.heavy))
                        .foregroundStyle(Color.Theme.primaryBlue)
                    Text("rank.progression.xp_to_next".localized(
                        (band.xpToNextRank ?? 0).formatted(),
                        nextTitle
                    ))
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.Theme.softBrown)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }

                rankIconBadge(systemName: nextIcon, rankLevel: nextLevel)
            }
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
            let r = rankBarCornerRadius

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: r, style: .continuous)
                    .fill(Color.Theme.softBrown.opacity(0.15))

                HStack(spacing: 0) {
                    if primaryWidth > 0 {
                        UnevenRoundedRectangle(
                            topLeadingRadius: r,
                            bottomLeadingRadius: r,
                            bottomTrailingRadius: gainWidth > 0 ? 0 : r,
                            topTrailingRadius: gainWidth > 0 ? 0 : r,
                            style: .continuous
                        )
                        .fill(Color.Theme.primaryBlue)
                        .frame(width: primaryWidth)
                    }
                    if gainWidth > 0 {
                        UnevenRoundedRectangle(
                            topLeadingRadius: primaryWidth > 0 ? 0 : r,
                            bottomLeadingRadius: primaryWidth > 0 ? 0 : r,
                            bottomTrailingRadius: r,
                            topTrailingRadius: r,
                            style: .continuous
                        )
                        .fill(Color.Theme.accentYellow)
                        .frame(width: gainWidth)
                    }
                }
            }
        }
        .frame(height: rankBarHeight)
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
        parts.append(contentsOf: presentation.lines.map { line in
            var lineParts = [line.title, "xp.toast.grant.xp_format".localized(line.xpAmount)]
            if let subtitle = line.subtitle, !subtitle.isEmpty {
                lineParts.insert(subtitle, at: 1)
            }
            return lineParts.joined(separator: ", ")
        })
        if let band = presentation.rankBand {
            parts.append("rank.progression.rank_label".localized(band.currentRankLevel))
            parts.append(band.currentRankTitle)
            if band.isMaxRank {
                parts.append("xp.toast.rank_band.max_rank".localized)
            } else if let nextTitle = band.nextRankTitle, let xpToNext = band.xpToNextRank {
                parts.append("rank.progression.xp_to_next".localized(xpToNext.formatted(), nextTitle))
            }
        }
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
                    subtitle: nil,
                    xpAmount: 19
                ),
                XpGainToastLine(
                    id: "return_streak",
                    title: "2 day streak",
                    subtitle: nil,
                    xpAmount: 5
                )
            ],
            rankBand: XpGainToastRankBand(
                currentRankLevel: 2,
                currentRankTitle: "Road Warrior",
                currentRankIcon: "car.2.fill",
                nextRankLevel: 3,
                nextRankTitle: "Highway Hero of the Open Road",
                nextRankIcon: "flame.fill",
                xpToNextRank: 4500000,
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
                    subtitle: "Pending resolution",
                    xpAmount: 10
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
