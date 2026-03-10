//
//  AvatarStackView.swift
//  LicensePlateApp
//
//  Stacked avatars (e.g. who found a state); first on top, others greyed; tap opens list.
//

import SwiftUI

struct AvatarStackView: View {
    let users: [AppUser]
    let maxDisplay: Int
    let avatarSize: CGFloat
    let onTap: (() -> Void)?
    
    init(
        users: [AppUser],
        maxDisplay: Int = 3,
        avatarSize: CGFloat = 32,
        onTap: (() -> Void)? = nil
    ) {
        self.users = Array(users.prefix(maxDisplay + 1))
        self.maxDisplay = maxDisplay
        self.avatarSize = avatarSize
        self.onTap = onTap
    }
    
    var body: some View {
        HStack(spacing: -avatarSize * 0.35) {
            ForEach(Array(users.enumerated()), id: \.element.id) { index, user in
                AvatarImageView(
                    avatarId: user.avatarId,
                    size: avatarSize, showRing: true, legacyFallbackImageName: user.defaultImageName
                )
                .overlay(
                    Circle()
                        .stroke(Color.Theme.background, lineWidth: 1.5)
                )
                .opacity(index == 0 ? 1.0 : 0.75)
            }
        }
        .onTapGesture {
            onTap?()
        }
    }
}

#Preview {
    let u1 = AppUser(userName: "A", avatarColor: .blue, avatarType: .dog)
    u1.avatarId = "navigator_raccoon"
    let u2 = AppUser(userName: "B", avatarColor: .green, avatarType: .cat)
    u2.avatarId = "scout_otter"
    return AvatarStackView(users: [u1, u2], maxDisplay: 3, avatarSize: 36)
        .padding()
}
