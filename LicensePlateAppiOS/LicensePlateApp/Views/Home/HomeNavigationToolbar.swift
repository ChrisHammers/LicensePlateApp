//
//  HomeNavigationToolbar.swift
//  LicensePlateApp
//

import SwiftUI

struct HomeNavigationToolbar: ToolbarContent {
    let streakPresentation: ReturnStreakPresentation
    let isStreakVisible: Bool
    let displayName: String?
    let currentUser: AppUser?
    /// Preview / test override. Production passes `nil` so the button observes `SocialInboxBadgeService`.
    var pendingInviteBadgeCountOverride: Int? = nil
    let onStreakTap: () -> Void
    let onTravelLogTap: () -> Void
    let onSettingsTap: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            HomeToolbarPrincipalView(
                streakPresentation: streakPresentation,
                isStreakVisible: isStreakVisible,
                displayName: displayName
            ) {
                onStreakTap()
            }
        }
        ToolbarItem(placement: .topBarLeading) {
            Button(action: onTravelLogTap) {
                Image(systemName: "map.fill")
                    .foregroundStyle(Color.Theme.primaryBlue)
            }
            .accessibilityLabel("Travel Log".localized)
            .accessibilityHint("Review old Trips".localized)
        }
        ToolbarItem(placement: .topBarTrailing) {
            // Nested View observes the badge service so toolbar chrome updates while staying on home.
            HomeSettingsAvatarButton(
                currentUser: currentUser,
                badgeCountOverride: pendingInviteBadgeCountOverride,
                onSettingsTap: onSettingsTap
            )
        }
    }
}

/// Settings avatar in the home toolbar. Observes social inbox counts so `.badge` stays live
/// (plain `ToolbarContent` + passed `Int` often fails to redraw while the root stays mounted).
private struct HomeSettingsAvatarButton: View {
    @ObservedObject private var socialInboxBadges = SocialInboxBadgeService.shared
    let currentUser: AppUser?
    let badgeCountOverride: Int?
    let onSettingsTap: () -> Void

    private var pendingInviteBadgeCount: Int {
        badgeCountOverride ?? socialInboxBadges.totalPendingInviteCount
    }

    var body: some View {
        Button(action: onSettingsTap) {
            if let user = currentUser {
                AvatarView(user: user, size: 34, showRing: true)
            } else {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.Theme.primaryBlue)
            }
        }
        .badge(pendingInviteBadgeCount)
        .id(pendingInviteBadgeCount)
        .accessibilityLabel(settingsAccessibilityLabel)
        .accessibilityHint("Opens app settings".localized)
    }

    private var settingsAccessibilityLabel: String {
        if pendingInviteBadgeCount > 0 {
            return "\("Settings".localized), \("social.inbox.a11y.avatar_pending".localized(pendingInviteBadgeCount))"
        }
        return "Settings".localized
    }
}

private struct HomeToolbarPrincipalView: View {
    let streakPresentation: ReturnStreakPresentation
    let isStreakVisible: Bool
    let displayName: String?
    let onStreakTap: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            Text("RoadTrip Royale")
                .font(.system(.headline, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(Color.Theme.primaryBlue)
            if isStreakVisible {
                ReturnStreakChipView(presentation: streakPresentation, onTap: onStreakTap)
            }
            if let displayName {
                Text(displayName)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(principalAccessibilityLabel)
    }

    private var principalAccessibilityLabel: String {
        let title = "RoadTrip Royale".localized
        if let displayName {
            return "\(title), \(displayName)"
        }
        return title
    }
}

#Preview("Home toolbar principal") {
    NavigationStack {
        Text("Home")
            .toolbar {
                HomeNavigationToolbar(
                    streakPresentation: ReturnStreakPresentation(
                        currentStreak: 3,
                        isVisible: true,
                        accessibilityLabel: "3 day return streak",
                        accessibilityHint: "Find a plate today to keep your streak."
                    ),
                    isStreakVisible: true,
                    displayName: "Chris",
                    currentUser: nil,
                    pendingInviteBadgeCountOverride: 2,
                    onStreakTap: {},
                    onTravelLogTap: {},
                    onSettingsTap: {}
                )
            }
    }
}
