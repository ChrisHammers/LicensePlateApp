//
//  XpPendingBadgeView.swift
//  LicensePlateApp
//

import SwiftUI

struct XpPendingBadgeView: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.Theme.primaryBlue)
            Text("xp.pending.badge.short".localized)
                .font(.system(.caption2, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(Color.Theme.softBrown)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.Theme.cardBackground)
                .overlay(Capsule().stroke(Color.Theme.primaryBlue.opacity(0.35), lineWidth: 1))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("xp.pending.badge.a11y".localized)
    }
}

#Preview {
    XpPendingBadgeView()
        .padding()
}
