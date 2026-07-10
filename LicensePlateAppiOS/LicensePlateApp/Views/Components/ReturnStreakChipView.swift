//
//  ReturnStreakChipView.swift
//  LicensePlateApp
//

import SwiftUI

struct ReturnStreakChipView: View {
    let presentation: ReturnStreakPresentation
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.orange)
                Text("\(presentation.currentStreak)")
                    .font(.system(.caption2, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.softBrown)
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(minHeight: 24)
            .background(
                Capsule()
                    .fill(Color.Theme.cardBackground)
                    .overlay(Capsule().stroke(Color.Theme.primaryBlue.opacity(0.35), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(presentation.accessibilityLabel)
        .accessibilityHint(presentation.accessibilityHint)
    }
}

#Preview("Return streak chip") {
    ReturnStreakChipView(
        presentation: ReturnStreakPresentation(
            currentStreak: 3,
            isVisible: true,
            accessibilityLabel: "3 day return streak",
            accessibilityHint: "Find a plate today to keep your streak."
        ),
        onTap: {}
    )
    .padding()
}
