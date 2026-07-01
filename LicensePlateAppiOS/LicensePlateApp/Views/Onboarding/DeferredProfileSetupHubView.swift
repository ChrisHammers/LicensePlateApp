//
//  DeferredProfileSetupHubView.swift
//  LicensePlateApp
//
//  Settings entry for optional profile steps deferred from quick solo first session.
//

import SwiftUI
import SwiftData

struct DeferredProfileSetupHubView: View {
    @EnvironmentObject private var authService: FirebaseAuthService
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var setupStore = DeferredProfileSetupStore.shared

    @StateObject private var onboardingCoordinator = OnboardingCoordinator()
    @State private var activeStep: DeferredSetupStep?

    private var pendingSteps: [DeferredSetupStep] {
        setupStore.pendingSteps(for: authService.currentUser)
    }

    var body: some View {
        AppBackgroundView {
            List {
                if pendingSteps.isEmpty {
                    Section {
                        Text("deferred_setup.all_complete".localized)
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                    }
                    .listRowBackground(Color.Theme.cardBackground)
                } else {
                    Section {
                        ForEach(pendingSteps) { step in
                            Button {
                                FirstSessionAnalyticsService.shared.recordDeferredSetupStepOpened(
                                    stepId: step.rawValue,
                                    source: "settings_hub"
                                )
                                activeStep = step
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: step.systemImage)
                                        .foregroundStyle(Color.Theme.primaryBlue)
                                        .frame(width: 28)
                                        .accessibleDecorative()
                                    Text(step.localizedTitle)
                                        .font(.system(.body, design: .rounded))
                                        .foregroundStyle(Color.Theme.primaryBlue)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(Color.Theme.softBrown)
                                        .accessibleDecorative()
                                }
                            }
                            .accessibilityHint("Opens this setup step".localized)
                            .listRowBackground(Color.Theme.cardBackground)
                        }
                    } header: {
                        Text("Complete your profile".localized)
                    } footer: {
                        Text("deferred_setup.footer".localized)
                            .font(.system(.caption, design: .rounded))
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Complete your profile".localized)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $activeStep) { step in
            deferredStepSheet(step)
        }
    }

    @ViewBuilder
    private func deferredStepSheet(_ step: DeferredSetupStep) -> some View {
        NavigationStack {
            switch step {
            case .avatar:
                OnboardingBackgroundView {
                    OnboardingAvatarPickerView(
                        coordinator: onboardingCoordinator,
                        onNext: {
                            complete(step)
                        }
                    )
                    .environmentObject(authService)
                }
            case .account:
                OnboardingBackgroundView {
                    OnboardingAccountCreationView(
                        coordinator: onboardingCoordinator,
                        onNext: {
                            complete(step)
                        }
                    )
                    .environmentObject(authService)
                }
//            case .family:
//                OnboardingBackgroundView {
//                    OnboardingCreateFamilyView(
//                        coordinator: onboardingCoordinator,
//                        onNext: {
//                            complete(step)
//                        }
//                    )
//                    .environmentObject(authService)
//                }
            case .notifications:
                PrivacyPermissionsView(onDone: { complete(step) })
            }
        }
    }

    private func complete(_ step: DeferredSetupStep) {
        setupStore.markCompleted(step)
        FirstSessionAnalyticsService.shared.recordDeferredSetupStepCompleted(stepId: step.rawValue)
        activeStep = nil
    }
}

#Preview {
    NavigationStack {
        DeferredProfileSetupHubView()
            .environmentObject(FirebaseAuthService())
    }
}
