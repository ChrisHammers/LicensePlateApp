//
//  AvatarBadgeView.swift
//  LicensePlateApp
//
//  Avatar + optional single equipped badge icon (MVP: one slot).
//

import SwiftUI

struct AvatarBadgeView: View {
    let avatarId: String?
    let legacyFallbackImageName: String?
    let equippedBadgeId: String?
    let avatarSize: CGFloat
    let badgeSize: CGFloat
    
    init(
        avatarId: String? = nil,
        legacyFallbackImageName: String? = nil,
        equippedBadgeId: String? = nil,
        avatarSize: CGFloat = 80,
        badgeSize: CGFloat = 28
    ) {
        self.avatarId = avatarId
        self.legacyFallbackImageName = legacyFallbackImageName
        self.equippedBadgeId = equippedBadgeId
        self.avatarSize = avatarSize
        self.badgeSize = badgeSize
    }
    
    init(user: AppUser, avatarSize: CGFloat = 80, badgeSize: CGFloat = 28) {
        self.avatarId = user.avatarId
        self.legacyFallbackImageName = user.defaultImageName
        self.equippedBadgeId = user.equippedBadgeId
        self.avatarSize = avatarSize
        self.badgeSize = badgeSize
    }
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AvatarImageView(
                avatarId: avatarId,
                size: avatarSize,
                showRing: true,
                customImageURL: nil,
                legacyFallbackImageName: legacyFallbackImageName
            )
            if let badgeId = equippedBadgeId, UserBadgeCatalog.definition(byId: badgeId) != nil {
                UserBadgePillView(badgeId: badgeId, size: badgeSize)
                    .offset(x: 2, y: 2)
            }
        }
    }
}

#Preview("With badge") {
    AvatarBadgeView(
        avatarId: "navigator_raccoon",
        equippedBadgeId: "first_plate_found",
        avatarSize: 100,
        badgeSize: 32
    )
    .padding()
}

#Preview("No badge") {
    AvatarBadgeView(avatarId: "scout_otter", avatarSize: 80)
        .padding()
}
