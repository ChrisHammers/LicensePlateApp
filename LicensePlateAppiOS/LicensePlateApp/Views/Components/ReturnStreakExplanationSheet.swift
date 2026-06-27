//
//  ReturnStreakExplanationSheet.swift
//  LicensePlateApp
//

import SwiftUI

struct ReturnStreakExplanationSheet: View {
    let currentStreak: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(Color.orange)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(streakCountText)
                            .font(.system(.title2, design: .rounded))
                            .fontWeight(.bold)
                            .foregroundStyle(Color.Theme.primaryBlue)
                        Text("return_streak.explanation.subtitle".localized)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(streakCountText)

                Text("return_streak.explanation.body".localized)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(24)
            .navigationTitle("return_streak.explanation.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done".localized) { dismiss() }
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                        .accessibilityLabel("Done".localized)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var streakCountText: String {
        String(format: "return_streak.celebration.title".localized, currentStreak)
    }
}

#Preview("Return streak explanation") {
    ReturnStreakExplanationSheet(currentStreak: 5)
}
