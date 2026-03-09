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
        case .seasonal, .specialPromotion: return "This avatar is available through a limited-time offer.".localized
        case .guest: return "This avatar is available to everyone.".localized
            /*
             case .signedUp:
             return "Create an account to unlock this avatar."
         case .gold:
             return "Upgrade to Gold to unlock this avatar."
         case .royale:
             return "Upgrade to Royale to unlock this avatar."
         case .family:
             return "Join a family to unlock this avatar."
         case .familyPass:
             return "This avatar unlocks through Family Pass."
         case .founder:
             return "This avatar is reserved for Founder players."
         case .lifetime:
             return "This avatar unlocks with an eligible Lifetime entitlement."
         case .seasonal:
             return "This is a special seasonal avatar."
         case .promo:
             return "This avatar unlocks through a promotion."
         case .purchase:
             return "This avatar requires direct purchase."
         case .achievement(let name):
             return "This avatar unlocks by completing Achievement \(name)."
         case .free, .none:
             return "This avatar is currently unavailable."
             */
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
