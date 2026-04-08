//
//  LifetimeStatsProfileStatsSection.swift
//  LicensePlateApp
//
//  Profile “Trip statistics” block: localized, accessible, loading/error states.
//

import SwiftUI

struct LifetimeStatsProfileStatsSection: View {
    @ObservedObject var viewModel: LifetimeStatsProfileViewModel

    var body: some View {
        LifetimeStatsProfileStatsSectionContent(
            stats: viewModel.stats,
            isRecomputing: viewModel.isRecomputing,
            lastError: viewModel.lastError,
            onRetry: { viewModel.retryRefresh() }
        )
    }
}

/// Values-only content for production binding and SwiftUI previews.
struct LifetimeStatsProfileStatsSectionContent: View {
    let stats: UserLifetimeStats?
    let isRecomputing: Bool
    let lastError: String?
    let onRetry: () -> Void

    var body: some View {
        Section {
            if isRecomputing {
                HStack(spacing: 12) {
                    ProgressView()
                        .accessibilityLabel("profile.lifetime_stats.updating.a11y".localized)
                    Text("profile.lifetime_stats.updating".localized)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }

            if let err = lastError, !err.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("profile.lifetime_stats.error_title".localized)
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                    Text(err)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                    Button("profile.lifetime_stats.retry".localized, action: onRetry)
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.semibold)
                }
                .padding(.vertical, 4)
            }

            if let s = stats {
                statRow(
                    titleKey: "profile.lifetime_stats.completed_trips",
                    value: "\(s.totalCompletedTrips)",
                    a11yHint: "profile.lifetime_stats.completed_trips.a11y"
                )
                statRow(
                    titleKey: "profile.lifetime_stats.games_played",
                    value: "\(s.totalGamesPlayed)",
                    a11yHint: "profile.lifetime_stats.games_played.a11y"
                )
                statRow(
                    titleKey: "profile.lifetime_stats.discoveries",
                    value: "\(s.totalDiscoveries)",
                    a11yHint: "profile.lifetime_stats.discoveries.a11y"
                )
                statRow(
                    titleKey: "profile.lifetime_stats.weighted_score",
                    value: formatScore(s.totalWeightedScore),
                    a11yHint: "profile.lifetime_stats.weighted_score.a11y"
                )
                statRow(
                    titleKey: "profile.lifetime_stats.family_trips",
                    value: "\(s.familyOnlyTripsCount)",
                    a11yHint: "profile.lifetime_stats.family_trips.a11y"
                )
            } else if !isRecomputing && (lastError == nil || lastError?.isEmpty == true) {
                Text("profile.lifetime_stats.empty".localized)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
            }
        } header: {
            Text("profile.lifetime_stats.title".localized)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Color.Theme.primaryBlue)
        }
        .textCase(nil)
        .listRowBackground(Color.clear)
        .listRowInsets(.init(top: 8, leading: 20, bottom: 8, trailing: 20))
    }

    private func statRow(titleKey: String, value: String, a11yHint: String) -> some View {
        HStack {
            Text(titleKey.localized)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.Theme.primaryBlue)
            Spacer()
            Text(value)
                .font(.system(.body, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(Color.Theme.softBrown)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(titleKey.localized))
        .accessibilityValue(Text(value))
        .accessibilityHint(Text(a11yHint.localized))
    }

    private func formatScore(_ v: Double) -> String {
        if v.rounded() == v {
            return String(format: "%.0f", v)
        }
        return String(format: "%.1f", v)
    }
}

#Preview("Lifetime stats — loading") {
    List {
        LifetimeStatsProfileStatsSectionContent(
            stats: nil,
            isRecomputing: true,
            lastError: nil,
            onRetry: {}
        )
    }
    .listStyle(.insetGrouped)
}

#Preview("Lifetime stats — loaded") {
    List {
        LifetimeStatsProfileStatsSectionContent(
            stats: UserLifetimeStats(
                totalCompletedTrips: 3,
                totalGamesPlayed: 5,
                totalDiscoveries: 42,
                totalWeightedScore: 40.5,
                familyOnlyTripsCount: 1,
                lastComputedAt: Date()
            ),
            isRecomputing: false,
            lastError: nil,
            onRetry: {}
        )
    }
    .listStyle(.insetGrouped)
}

#Preview("Lifetime stats — error") {
    List {
        LifetimeStatsProfileStatsSectionContent(
            stats: nil,
            isRecomputing: false,
            lastError: "Network unavailable",
            onRetry: {}
        )
    }
    .listStyle(.insetGrouped)
}
