//
//  AvatarUnlockExplanationSheet.swift
//  LicensePlateApp
//
//  Sheet explaining locked avatar and upsell (e.g. Sign up to unlock).
//

import SwiftUI

struct AvatarUnlockExplanationSheet: View {
    let unlockSource: AvatarUnlockSource
    let avatarName: String
    let onDismiss: () -> Void
    
    private var title: String {
        switch unlockSource {
        case .guest: return "Available to everyone"
        case .signedUp: return "Sign up to unlock"
        case .gold: return "Gold member avatar"
        case .royale: return "Royale member avatar"
        case .family: return "Join a family to unlock"
        case .familyPass: return "Family Pass avatar"
        case .founder: return "Founder exclusive"
        case .seasonal: return "Seasonal unlock"
        case .specialPromotion: return "Special promotion"
        }
    }
    
    private var message: String {
        switch unlockSource {
        case .signedUp: return "Create an account to use this avatar and save your progress."
        case .gold: return "Upgrade to Gold to unlock this avatar and more."
        case .royale: return "Upgrade to Royale for access to this avatar."
        case .family: return "Join or create a family to unlock family avatars."
        case .familyPass: return "Your family's organizer has Gold or Royale—you get Family Pass avatars!"
        case .founder: return "This avatar is for our founding members."
        case .seasonal, .specialPromotion: return "This avatar is available through a limited-time offer."
        case .guest: return "This avatar is available to everyone."
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: unlockSource.lockIconName)
                    .font(.system(size: 48))
                    .foregroundStyle(Color.Theme.primaryBlue)
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
                    Button("Done") {
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
