//
//  OnboardingAvatarPickerView.swift
//  LicensePlateApp
//
//  Choose your avatar or skip; same AvatarPickerView used in settings.
//

import SwiftUI
import SwiftData

struct OnboardingAvatarPickerView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authService: FirebaseAuthService
    @ObservedObject var coordinator: OnboardingCoordinator
    let onNext: () -> Void
    
    @StateObject private var viewModel = AvatarPickerViewModel(catalogService: .shared)
    @StateObject private var paywallViewModel = PaywallViewModel()
    @State private var unlockSheetPayload: AvatarUnlockSheetPayload?
    @State private var showPaywallSheet = false
    @State private var paywallUnlockSource: AvatarUnlockSource?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    Text("Choose your avatar".localized)
                        .font(.system(.largeTitle, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                        .accessibleHeader("Choose your avatar".localized)
                    
                    Text("Pick one you like or skip to keep your current avatar.".localized)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    AvatarPickerView(
                        items: viewModel.displayItems,
                        selectedId: Binding(
                            get: { viewModel.selectedId },
                            set: { viewModel.selectedId = $0 }
                        ),
                        onLockedTap: { item, source in
                            AnalyticsService.shared.log(.avatarLockedTapped(avatarId: item.id, unlockSource: source.rawValue))
                            unlockSheetPayload = AvatarUnlockSheetPayload(unlockSource: source, avatarName: item.displayName)
                        },
                        onSelected: nil
                    )
                    .frame(height: 196)
                    .padding(.vertical, 16)
                    
                    VStack(spacing: 8) {
                        Text("Selected".localized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(selectedAvatarDisplayName)
                            .font(.headline)
                            .foregroundStyle(selectedAvatarDisplayName == "None".localized ? .secondary : .primary)
                    }
                }
                .padding(.vertical, 32)
                .padding(.horizontal, 24)
            }
            
            VStack(spacing: 16) {
                Button {
                    saveAndContinue()
                } label: {
                    Text("Continue".localized)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.Theme.primaryBlue)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                }
                .accessibleButton(label: "Continue".localized, hint: "Save avatar and continue".localized)
                
                Button {
                    onNext()
                } label: {
                    Text("Skip".localized)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.Theme.primaryBlue)
                }
                .accessibleButton(label: "Skip".localized, hint: "Keep current avatar and continue".localized)
            }
            .padding(24)
        }
        .onAppear {
            viewModel.setUser(authService.currentUser)
            if viewModel.selectedId == nil, let user = authService.currentUser {
                viewModel.selectedId = user.avatarId ?? AvatarCatalog.randomGuestAvatarId()
            }
            AnalyticsService.shared.log(.avatarPickerOpened(source: "onboarding"))
        }
        .overlay {
            if let payload = unlockSheetPayload {
                AvatarUnlockPopupView(
                    unlockSource: payload.unlockSource,
                    avatarName: payload.avatarName,
                    onDismiss: { unlockSheetPayload = nil },
                    onShowPaywall: { source in
                        paywallUnlockSource = source
                        unlockSheetPayload = nil
                        showPaywallSheet = true
                    }
                )
            }
        }
        .sheet(isPresented: $showPaywallSheet) {
            PaywallView(viewModel: paywallViewModel, onDismiss: { showPaywallSheet = false })
                .onAppear {
                    paywallViewModel.setUnlockContext(paywallUnlockSource)
                }
        }
    }
    
    private var selectedAvatarDisplayName: String {
        guard let id = viewModel.selectedId else { return "None".localized }
        return viewModel.displayItems.first(where: { $0.id == id })?.displayName ?? "None".localized
    }

    private func saveAndContinue() {
        guard let user = authService.currentUser else {
            onNext()
            return
        }
        if let id = viewModel.selectedId {
            user.avatarId = id
            user.lastUpdated = .now
            try? modelContext.save()
            Task {
                try? await authService.saveUserDataToFirestore(user)
            }
            AnalyticsService.shared.log(.avatarSaved(avatarId: id, source: "onboarding"))
        }
        onNext()
    }
}

#Preview {
    OnboardingAvatarPickerView(coordinator: OnboardingCoordinator(), onNext: {})
        .environmentObject(FirebaseAuthService())
}
