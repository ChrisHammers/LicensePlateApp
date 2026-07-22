//
//  UserDetailNavigationLink.swift
//  LicensePlateApp
//
//  Shared push navigation to StandardProfileView for avatar / name / username taps.
//

import SwiftUI

enum UserDetailNavigation {
    /// True when `user` matches the signed-in account id (firebase UID or local id).
    static func isSelfProfile(user: AppUser, currentUserId: String?) -> Bool {
        guard let currentUserId, !currentUserId.isEmpty else { return false }
        if user.id == currentUserId { return true }
        if let firebaseUID = user.firebaseUID, firebaseUID == currentUserId { return true }
        return false
    }
}

/// Pushes ``StandardProfileView`` when the label (avatar, name, or username) is tapped.
struct UserDetailNavigationLink<Label: View>: View {
    let user: AppUser
    var isSelfProfile: Bool = false
    @ViewBuilder var label: () -> Label

    var body: some View {
        NavigationLink {
            StandardProfileView(user: user, isSelfProfile: isSelfProfile)
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens profile".localized)
    }
}

#Preview {
    NavigationStack {
        List {
            UserDetailNavigationLink(
                user: AppUser(
                    id: PreviewConstants.userId1,
                    userName: "preview_driver",
                    firebaseUID: PreviewConstants.userId1
                )
            ) {
                UserIdentityRowView(
                    avatarId: "navigator_raccoon",
                    displayName: "Preview Driver",
                    subtitle: "@preview_driver",
                    avatarSize: 50
                )
            }
        }
    }
}
