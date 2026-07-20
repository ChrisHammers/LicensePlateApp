//
//  UserIdentityRowView.swift
//  LicensePlateApp
//
//  Reusable row: avatar + name + optional badge; for friends, family, trip lists.
//

import SwiftUI

struct UserIdentityRowView: View {
    let avatarId: String?
    let legacyFallbackImageName: String?
    let displayName: String
    let subtitle: String?
    let equippedBadgeId: String?
    let avatarSize: CGFloat
    
    init(
        avatarId: String? = nil,
        legacyFallbackImageName: String? = nil,
        displayName: String,
        subtitle: String? = nil,
        equippedBadgeId: String? = nil,
        avatarSize: CGFloat = 44
    ) {
        self.avatarId = avatarId
        self.legacyFallbackImageName = legacyFallbackImageName
        self.displayName = displayName
        self.subtitle = subtitle
        self.equippedBadgeId = equippedBadgeId
        self.avatarSize = avatarSize
    }
    
    init(user: AppUser, subtitle: String? = nil, avatarSize: CGFloat = 44) {
        self.avatarId = user.avatarId
        self.legacyFallbackImageName = nil
        self.displayName = user.displayName
        self.subtitle = subtitle ?? (user.userName.isEmpty ? nil : "@\(user.userName)")
        self.equippedBadgeId = user.equippedBadgeId
        self.avatarSize = avatarSize
    }
    
    var body: some View {
        HStack(spacing: 12) {
            AvatarBadgeView(
                avatarId: avatarId,
                legacyFallbackImageName: legacyFallbackImageName,
                equippedBadgeId: equippedBadgeId,
                avatarSize: avatarSize,
                badgeSize: max(16, avatarSize * 0.36)
            )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                if let sub = subtitle, !sub.isEmpty {
                    Text(sub)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                }
            }
            
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    List {
        UserIdentityRowView(
            avatarId: "navigator_raccoon",
            displayName: "Alex Scout",
            subtitle: "@alexscout",
            equippedBadgeId: "first_plate_found"
        )
        UserIdentityRowView(
            avatarId: "scout_otter",
            displayName: "Legacy User",
            subtitle: "@legacy"
        )
    }
}
