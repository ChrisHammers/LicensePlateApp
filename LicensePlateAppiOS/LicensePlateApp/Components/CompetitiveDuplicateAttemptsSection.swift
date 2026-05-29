//
//  CompetitiveDuplicateAttemptsSection.swift
//  LicensePlateApp
//
//  Competitive mode: personal duplicate-rejection history (labels from projection only).
//

import SwiftUI

struct CompetitiveDuplicateAttemptsSection: View {
    let attempts: [CompetitiveDuplicateAttempt]
    let regionDisplayName: (String) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your duplicate attempts".localized)
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(Color.Theme.primaryBlue)
                .accessibilityAddTraits(.isHeader)

            if attempts.isEmpty {
                Text("No duplicate attempts yet".localized)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                    .accessibilityLabel("No duplicate attempts yet".localized)
            } else {
                ForEach(attempts) { attempt in
                    HStack {
                        Text(regionDisplayName(attempt.targetId))
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.Theme.primaryBlue)
                        Spacer()
                        Text(attempt.timestamp.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "\(regionDisplayName(attempt.targetId)), \(attempt.timestamp.formatted(date: .abbreviated, time: .shortened))"
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
