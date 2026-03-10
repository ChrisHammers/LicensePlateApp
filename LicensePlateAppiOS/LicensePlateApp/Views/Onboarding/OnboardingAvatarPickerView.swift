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
    @State private var unlockSheetPayload: AvatarUnlockSheetPayload?
    
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
                            unlockSheetPayload = AvatarUnlockSheetPayload(unlockSource: source, avatarName: item.displayName)
                            AnalyticsService.shared.log("avatar_locked_tapped", parameters: ["avatar_id": item.id, "unlock_source": source.rawValue])
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
            AnalyticsService.shared.log("avatar_picker_opened", parameters: ["source": "onboarding"])
        }
        .sheet(item: $unlockSheetPayload) { payload in
            AvatarUnlockExplanationSheet(
                unlockSource: payload.unlockSource,
                avatarName: payload.avatarName,
                onDismiss: { unlockSheetPayload = nil }
            )
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
            AnalyticsService.shared.log("avatar_saved", parameters: ["avatar_id": id, "source": "onboarding"])
        }
        onNext()
    }
}

#Preview {
    OnboardingAvatarPickerView(coordinator: OnboardingCoordinator(), onNext: {})
        .environmentObject(FirebaseAuthService())
}
