//
//  PaywallView.swift
//  LicensePlateApp
//
//  Paywall UI: packages from ViewModel, Restore, Maybe Later. No store logic in view.
//

import SwiftUI

struct PaywallView: View {
    @ObservedObject var viewModel: PaywallViewModel
    let onDismiss: () -> Void
    /// Optional primary button (e.g. "Continue" in onboarding). When nil, only "Maybe Later" is shown.
    var primaryActionTitle: String? = nil
    var primaryAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    Text(viewModel.unlockReasonTitle)
                        .font(.system(.largeTitle, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                        .accessibleHeader(viewModel.unlockReasonTitle)
                        .multilineTextAlignment(.center)

                    Text(viewModel.unlockReasonMessage)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    if let message = viewModel.errorMessage {
                        Text(message)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }

                    if viewModel.isLoading {
                        ProgressView()
                            .padding(.vertical, 24)
                    } else if viewModel.packages.isEmpty {
                        Text("Premium benefits coming soon".localized)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
                            .padding(.horizontal)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(viewModel.packages) { pkg in
                                PaywallPackageRow(
                                    package: pkg,
                                    isPurchasing: viewModel.isPurchasing
                                ) {
                                    Task { await viewModel.purchase(packageId: pkg.id) }
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical, 32)
                .padding(.bottom, 24)
            }

            VStack(spacing: 16) {
                if !viewModel.packages.isEmpty {
                    Button {
                        Task { await viewModel.restore() }
                    } label: {
                        Text("Restore Purchases".localized)
                            .font(.system(.body, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .foregroundStyle(Color.Theme.primaryBlue)
                    }
                    .disabled(viewModel.isRestoring)
                    .accessibleButton(label: "Restore Purchases".localized, hint: "Restore previous purchases".localized)
                }

                if let title = primaryActionTitle, let action = primaryAction {
                    Button {
                        viewModel.dismiss()
                        action()
                    } label: {
                        Text(title)
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Capsule().fill(Color.Theme.primaryBlue))
                            .foregroundStyle(.white)
                    }
                    .accessibleButton(label: title, hint: "Continues to next screen".localized)
                }

                Button {
                    viewModel.dismiss()
                    onDismiss()
                } label: {
                    Text("Maybe Later".localized)
                        .font(.system(.body, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .foregroundStyle(Color.Theme.softBrown)
                }
                .accessibleButton(label: "Maybe Later".localized, hint: "Dismiss paywall".localized)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .task {
            await viewModel.loadOfferings(source: "paywall")
        }
    }
}

// MARK: - Package row

private struct PaywallPackageRow: View {
    let package: PaywallPackage
    let isPurchasing: Bool
    let onPurchase: () -> Void

    var body: some View {
        Button(action: onPurchase) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(package.displayName)
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(.primary)
                    if let type = package.packageType, !type.isEmpty {
                        Text(type)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(package.displayPrice)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Color.Theme.primaryBlue)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
        }
        .disabled(isPurchasing)
        .accessibleButton(label: "\(package.displayName) \(package.displayPrice)", hint: "Purchase this package".localized)
    }
}

// MARK: - Previews

#Preview("Paywall - Loading") {
    let vm = PaywallViewModel()
    return PaywallView(viewModel: vm, onDismiss: {})
}

#Preview("Paywall - Empty") {
    let vm = PaywallViewModel()
    return PaywallView(viewModel: vm, onDismiss: {})
}
