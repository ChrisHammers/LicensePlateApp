//
//  StandardProfileView.swift
//  LicensePlateApp
//
//  Read-only profile for looked-up users; shared license hero + lifetime stats.
//

import SwiftUI

struct StandardProfileView: View {
    @StateObject private var viewModel: StandardProfileViewModel
    @ObservedObject private var entitlementService: EntitlementService

    private let xpProgressViewModel: XpProgressViewModel?
    private let lifetimeStatsViewModel: LifetimeStatsProfileViewModel?

    init(
        user: AppUser,
        isSelfProfile: Bool = false,
        lifetimeStatsViewModel: LifetimeStatsProfileViewModel? = nil,
        xpProgressViewModel: XpProgressViewModel? = nil,
        entitlementService: EntitlementService = .shared
    ) {
        self.lifetimeStatsViewModel = isSelfProfile ? lifetimeStatsViewModel : nil
        self.xpProgressViewModel = isSelfProfile ? xpProgressViewModel : nil
        _viewModel = StateObject(wrappedValue: StandardProfileViewModel(
            user: user,
            isSelfProfile: isSelfProfile,
            lifetimeStatsViewModel: lifetimeStatsViewModel,
            xpProgressViewModel: xpProgressViewModel
        ))
        self.entitlementService = entitlementService
    }

    var body: some View {
        AppBackgroundView {
            List {
                Section {
                    ProfileDriversLicenseCardSection(
                        license: viewModel.makeLicense(isRoyale: isRoyale),
                        user: viewModel.user
                    )
                }
                .listRowBackground(Color.clear)
                .listRowInsets(.init(top: 8, leading: 20, bottom: 8, trailing: 20))

                if let xpProgressViewModel {
                    ProfileXpProgressSection(viewModel: xpProgressViewModel)
                }

                LifetimeStatsProfileStatsSectionContent(
                    stats: viewModel.lifetimeStats,
                    isRecomputing: viewModel.isRecomputing,
                    isPendingServerSync: viewModel.isPendingServerSync,
                    lastError: viewModel.lastError,
                    onRetry: { viewModel.retryRefresh() }
                )
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(viewModel.user.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.onAppear() }
    }

    private var isRoyale: Bool {
        entitlementService.entitlementState(for: viewModel.user).effectiveTier >= .royale
    }
}
