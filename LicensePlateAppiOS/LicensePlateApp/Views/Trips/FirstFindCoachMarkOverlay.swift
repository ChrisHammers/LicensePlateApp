//
//  FirstFindCoachMarkOverlay.swift
//  LicensePlateApp
//
//  Non-blocking coach mark for the first plate find on the list tab.
//

import SwiftUI

struct FirstFindCoachMarkOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 28))
                .foregroundStyle(Color.Theme.primaryBlue)
                .accessibleDecorative()
            Text("Tap a plate to log your first find".localized)
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(Color.Theme.primaryBlue)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.Theme.cardBackground)
                .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
        )
        .scaleEffect(reduceMotion || !isPulsing ? 1.0 : 1.04)
        .animation(reduceMotion ? nil : .easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isPulsing)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tap a plate to log your first find".localized)
        .accessibilityHint("quick_solo.coach_mark.hint".localized)
        .accessibilitySortPriority(-1)
        .onAppear {
            if !reduceMotion {
                isPulsing = true
            }
            UIAccessibility.post(notification: .announcement, argument: "Tap a plate to log your first find".localized)
        }
    }
}

#Preview {
    FirstFindCoachMarkOverlay()
        .padding()
}
