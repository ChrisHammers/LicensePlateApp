//
//  UserSearchEmptyStateView.swift
//  LicensePlateApp
//
//  Empty results for Add Friend / Add Family search.
//

import SwiftUI

struct UserSearchEmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 44))
                .foregroundStyle(Color.Theme.softBrown.opacity(0.8))
                .accessibilityHidden(true)

            Text("No users found".localized)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Color.Theme.primaryBlue)
                .multilineTextAlignment(.center)

            Text("Try a different username or email.".localized)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\("No users found".localized). \("Try a different username or email.".localized)"
        )
    }
}

#Preview("User search empty") {
    List {
        Section {
            UserSearchEmptyStateView()
                .listRowBackground(Color.Theme.cardBackground)
        }
    }
    .listStyle(.insetGrouped)
}
