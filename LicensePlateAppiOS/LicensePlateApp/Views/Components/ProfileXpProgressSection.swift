//
//  ProfileXpProgressSection.swift
//  LicensePlateApp
//

import SwiftUI

struct ProfileXpProgressSection: View {
    @ObservedObject var viewModel: XpProgressViewModel

    var body: some View {
        Section {
            VStack(spacing: 12) {
                if let err = viewModel.lastError, !err.isEmpty {
                    Text(err)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.red.opacity(0.9))
                }

                if let xp = viewModel.serverFinalXp {
                    HStack {
                        Text("profile.xp.server_total".localized)
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(Color.Theme.primaryBlue)
                        Spacer()
                        Text("\(xp)")
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.Theme.softBrown)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("profile.xp.server_total".localized)
                    .accessibilityValue("\(xp)")
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("profile.xp.local_fallback_total".localized)
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(Color.Theme.primaryBlue)
                            Spacer()
                            Text("\(viewModel.displayedTotalXp)")
                                .font(.system(.body, design: .rounded))
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.Theme.softBrown)
                        }
                        Text(viewModel.ledgerProvisionalPending > 0 ? "profile.xp.local_fallback_note".localized : "profile.xp.server_total_loading".localized)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("profile.xp.local_fallback_total".localized)
                    .accessibilityValue("\(viewModel.displayedTotalXp)")
                }

                if viewModel.ledgerProvisionalPending > 0 {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(Color.Theme.primaryBlue)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("profile.xp.pending_ledger_line".localized(viewModel.ledgerProvisionalPending))
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(Color.Theme.softBrown)
                            ProjectedRankProgressView(
                                serverXp: viewModel.serverFinalXp ?? 0,
                                pendingLedgerXp: viewModel.ledgerProvisionalPending
                            )
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("profile.xp.pending_section.a11y".localized)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(Color.Theme.cardBackground)
            .cornerRadius(20)
            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
            .listRowBackground(Color.clear)
        } header: {
            Text("profile.xp.section_title".localized)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Color.Theme.primaryBlue)
        }
        .textCase(nil)
        .listRowBackground(Color.clear)
        .listRowInsets(.init(top: 8, leading: 20, bottom: 8, trailing: 20))
    }
}

#Preview("Profile XP section placeholder") {
    List {
        Text("profile.xp.section_title".localized)
            .font(.headline)
    }
}
