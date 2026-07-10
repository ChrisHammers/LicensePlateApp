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
            .padding(.bottom, 10)

            progressBar
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
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(line.title)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(line.xpDisplayText)
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

    @ViewBuilder
    private var progressBar: some View {
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
        let lineSummary = presentation.lines.map { line in
            var parts = [line.title, line.xpDisplayText]
            if let subtitle = line.subtitle, !subtitle.isEmpty {
                parts.insert(subtitle, at: 1)
            }
            return parts.joined(separator: ", ")
        }.joined(separator: "; ")
        return "xp.toast.a11y.label".localized(lineSummary)
    }
}

#Preview("Single line") {
    XpGainToastBanner(
        presentation: XpGainToastPresentation(
            lines: [
                XpGainToastLine(
                    id: "ledger|1",
                    title: "Texas found",
                    subtitle: nil,
                    xpDisplayText: "+10 XP"
                )
            ],
            expiresAt: Date().addingTimeInterval(4),
            dismissDuration: 4
        ),
        onDismiss: {}
    )
    .padding(.top, 8)
}

#Preview("Coalesced") {
    XpGainToastBanner(
        presentation: XpGainToastPresentation(
            lines: [
                XpGainToastLine(
                    id: "ledger|1",
                    title: "Texas found",
                    subtitle: nil,
                    xpDisplayText: "+10 XP"
                ),
                XpGainToastLine(
                    id: "ledger|2",
                    title: "California found",
                    subtitle: "Pending resolution",
                    xpDisplayText: "+10 XP pending"
                )
            ],
            expiresAt: Date().addingTimeInterval(4),
            dismissDuration: 4
        ),
        onDismiss: {}
    )
    .padding(.top, 8)
}
