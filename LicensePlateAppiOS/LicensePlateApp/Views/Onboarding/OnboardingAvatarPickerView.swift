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
    @State private var showUnlockSheet = false
    @State private var sheetUnlockSource: AvatarUnlockSource?
    @State private var sheetItem: AvatarDisplayItem?
    
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
                            sheetItem = item
                            sheetUnlockSource = source
                            showUnlockSheet = true
                            AnalyticsService.shared.log("avatar_locked_tapped", parameters: ["avatar_id": item.id, "unlock_source": source.rawValue])
                        },
                        onSelected: nil
                    )
                    .frame(height: 140)
                    .padding(.vertical, 16)
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
        .sheet(isPresented: $showUnlockSheet) {
            if let source = sheetUnlockSource {
                AvatarUnlockExplanationSheet(
                    unlockSource: source,
                    avatarName: sheetItem?.displayName ?? "",
                    onDismiss: {
                        showUnlockSheet = false
                        sheetItem = nil
                        sheetUnlockSource = nil
                    }
                )
            }
        }
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
