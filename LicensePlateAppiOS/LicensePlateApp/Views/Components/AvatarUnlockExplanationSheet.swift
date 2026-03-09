//
//  AvatarUnlockExplanationSheet.swift
//  LicensePlateApp
//
//  Sheet explaining locked avatar and upsell (e.g. Sign up to unlock).
//

import SwiftUI

/// Payload for presenting the unlock explanation sheet. Use with `sheet(item:)` so the sheet always has valid data.
struct AvatarUnlockSheetPayload: Identifiable {
    let id = UUID()
    let unlockSource: AvatarUnlockSource
    let avatarName: String
}

struct AvatarUnlockExplanationSheet: View {
    let unlockSource: AvatarUnlockSource
    let avatarName: String
    let onDismiss: () -> Void
    
    private var title: String {
        switch unlockSource {
        case .guest: return "Available to everyone".localized
        case .signedUp: return "Sign up to unlock".localized
        case .gold: return "Gold member avatar".localized
        case .royale: return "Royale member avatar".localized
        case .family: return "Join a family to unlock".localized
        case .familyPass: return "Family Pass avatar".localized
        case .founder: return "Founder exclusive".localized
        case .lifetime: return "Lifetime entitlement".localized
        case .achievement: return "Achievement unlock".localized
        case .seasonal: return "Seasonal unlock".localized
        case .specialPromotion: return "Special promotion".localized
        }
    }
    
    private var message: String {
        switch unlockSource {
        case .signedUp: return "Create an account to use this avatar and save your progress.".localized
        case .gold: return "Upgrade to Gold to unlock this avatar and more.".localized
        case .royale: return "Upgrade to Royale for access to this avatar.".localized
        case .family: return "Join or create a family to unlock family avatars.".localized
        case .familyPass: return "Your family's organizer has Gold or Royale—you get Family Pass avatars!".localized
        case .founder: return "This avatar is for our founding members.".localized
        case .lifetime: return "This avatar unlocks with an eligible Lifetime entitlement.".localized
        case .achievement: return "This avatar unlocks by completing an achievement.".localized
        case .seasonal, .specialPromotion: return "This avatar is available through a limited-time offer.".localized
        case .guest: return "This avatar is available to everyone.".localized
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(avatarName)
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.bold)
                AvatarLockOverlayView(unlockSource: unlockSource, style: .detailed)
                Text(title)
                    .font(.system(.title2, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                Text(message)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Spacer()
            }
            .padding(.top, 32)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done".localized) {
                        onDismiss()
                    }
                    .foregroundStyle(Color.Theme.primaryBlue)
                }
            }
        }
    }
}

#Preview {
    AvatarUnlockExplanationSheet(
        unlockSource: .signedUp,
        avatarName: "Dragon",
        onDismiss: {}
    )
}
