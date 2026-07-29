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
    let isCurrentUser: Bool

    private var resolvedDisplayName: String {
        ParticipantDisplayName.decorated(displayName, isCurrentUser: isCurrentUser)
    }

    init(
        avatarId: String? = nil,
        legacyFallbackImageName: String? = nil,
        displayName: String,
        subtitle: String? = nil,
        equippedBadgeId: String? = nil,
        avatarSize: CGFloat = 44,
        isCurrentUser: Bool = false
    ) {
        self.avatarId = avatarId
        self.legacyFallbackImageName = legacyFallbackImageName
        self.displayName = displayName
        self.subtitle = subtitle
        self.equippedBadgeId = equippedBadgeId
        self.avatarSize = avatarSize
        self.isCurrentUser = isCurrentUser
    }

    init(user: AppUser, subtitle: String? = nil, avatarSize: CGFloat = 44, isCurrentUser: Bool = false) {
        self.avatarId = user.avatarId
        self.legacyFallbackImageName = nil
        self.displayName = user.displayName
        self.subtitle = subtitle ?? (user.userName.isEmpty ? nil : "@\(user.userName)")
        self.equippedBadgeId = user.equippedBadgeId
        self.avatarSize = avatarSize
        self.isCurrentUser = isCurrentUser
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
                Text(resolvedDisplayName)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                if let sub = subtitle, !sub.isEmpty {
                    Text(sub)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
        UserIdentityRowView(
            avatarId: "navigator_raccoon",
            displayName: "You Person",
            subtitle: "@you",
            isCurrentUser: true
        )
    }
}
