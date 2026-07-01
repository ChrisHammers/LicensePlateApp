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

    @StateObject private var onboardingCoordinator = OnboardingCoordinator()
    @State private var activeStep: DeferredSetupStep?

    private var pendingSteps: [DeferredSetupStep] {
        DeferredProfileSetupStore.shared.pendingSteps(for: authService.currentUser)
    }

    var body: some View {
        List {
            if pendingSteps.isEmpty {
                Section {
                    Text("deferred_setup.all_complete".localized)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                }
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
                    }
                } header: {
                    Text("Complete Your Profile".localized)
                } footer: {
                    Text("deferred_setup.footer".localized)
                        .font(.system(.caption, design: .rounded))
                }
            }
        }
        .navigationTitle("Complete Your Profile".localized)
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
                OnboardingAvatarPickerView(
                    coordinator: onboardingCoordinator,
                    onNext: {
                        complete(step)
                    }
                )
                .environmentObject(authService)
            case .account:
                OnboardingAccountCreationView(
                    coordinator: onboardingCoordinator,
                    onNext: {
                        complete(step)
                    }
                )
                .environmentObject(authService)
            case .family:
                OnboardingCreateFamilyView(
                    coordinator: onboardingCoordinator,
                    onNext: {
                        complete(step)
                    }
                )
                .environmentObject(authService)
            case .notifications:
                PrivacyPermissionsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done".localized) {
                                complete(step)
                            }
                        }
                    }
            }
        }
    }

    private func complete(_ step: DeferredSetupStep) {
        DeferredProfileSetupStore.shared.markCompleted(step)
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
