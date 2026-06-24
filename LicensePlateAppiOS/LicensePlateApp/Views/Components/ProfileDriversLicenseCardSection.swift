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
    var showsAvatarEdit: Bool = false
    var onEditAvatar: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 12) {
            if showsAvatarEdit, let onEditAvatar {
                UserDriversLicenseCard(license: license, width: cardWidth) {
                    ProfileDriversLicensePortraitView(user: user)
                }.accessory(alignment: .bottomTrailing) {
                    LicenseCornerButton(systemImage: "pencil") {
                        onEditAvatar()
                    }
                    .allowsHitTesting(true)   // let the Menu own the tap
                }
            } else {
                UserDriversLicenseCard(license: license, width: cardWidth) {
                    ProfileDriversLicensePortraitView(user: user)
                }
            }
            
            //            if showsAvatarEdit, let onEditAvatar {
            //                Button(action: onEditAvatar) {
            //                    Image(systemName: "pencil")
            //                        .font(.system(size: 14, weight: .semibold))
            //                        .foregroundStyle(.white)
            //                        .frame(width: 32, height: 32)
            //                        .background(Circle().fill(Color.Theme.primaryBlue))
            //                }
            //                .offset(x: -8, y: -8)
            //                .accessibilityLabel("Change avatar".localized)
            //            }
            
            Text(user.displayName)
                .font(.system(.title3, design: .rounded))
                .fontWeight(.bold)
                .foregroundStyle(Color.Theme.primaryBlue)
            
            Text("@\(user.userName)")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}
