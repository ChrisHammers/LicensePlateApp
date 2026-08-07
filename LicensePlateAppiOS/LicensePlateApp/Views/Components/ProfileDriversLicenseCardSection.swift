//
//  ProfileDriversLicenseCardSection.swift
//  LicensePlateApp
//
//  Hero license card block for personal and standard profile screens.
//

import SwiftUI

struct ProfileDriversLicenseCardSection: View {
    let license: UserDriversLicense
    let user: AppUser
    var cardWidth: CGFloat = 340
    var style: LicenseStyle = .standard
    var showsAvatarEdit: Bool = false
    var showsLicenseCustomize: Bool = false
    var onEditAvatar: (() -> Void)? = nil
    var onCustomizeLicense: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            card
            Text(user.displayName)
                .font(.system(.title3, design: .rounded))
                .fontWeight(.bold)
                .foregroundStyle(Color.Theme.primaryBlue)

            Text("@\(user.userName)")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)

            /*
            if showsLicenseCustomize, onCustomizeLicense != nil {
                Button {
                    FeedbackService.shared.buttonTap()
                    onCustomizeLicense?()
                } label: {
                    Label("Customize explorers license".localized, systemImage: "paintpalette.fill")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Color.Theme.primaryBlue)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Choose an explorers license skin".localized)
            }
            */
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var card: some View {
        let base = UserDriversLicenseCard(license: license, width: cardWidth, style: style) {
            avatarPortrait
        }

        if showsLicenseCustomize, let onCustomizeLicense {
            base.accessory(alignment: .bottomTrailing) {
                LicenseCornerButton(systemImage: "paintpalette.fill") {
                    FeedbackService.shared.buttonTap()
                    onCustomizeLicense()
                }
                .accessibilityLabel("Customize explorers license".localized)
                .accessibilityHint("Choose an explorers license skin".localized)
            }
        } else {
            base
        }
    }

    @ViewBuilder
    private var avatarPortrait: some View {
        ProfileDriversLicensePortraitView(user: user)
            .overlay(alignment: .topTrailing) {
                if showsAvatarEdit, let onEditAvatar {
                    LicenseCornerButton(systemImage: "pencil", size: 22) {
                        FeedbackService.shared.buttonTap()
                        onEditAvatar()
                    }
                    .padding(.trailing, -8)
                    .padding(.top, -8)
                    .accessibilityLabel("Change avatar".localized)
                }
            }
    }
}

#Preview {
    ProfileDriversLicenseCardSection(
        license: .sample,
        user: AppUser(userName: "scout", firstName: "Scout", lastName: "Otter", avatarId: "scout_otter"),
        showsAvatarEdit: true,
        showsLicenseCustomize: true,
        onEditAvatar: {},
        onCustomizeLicense: {}
    )
    .padding()
}
