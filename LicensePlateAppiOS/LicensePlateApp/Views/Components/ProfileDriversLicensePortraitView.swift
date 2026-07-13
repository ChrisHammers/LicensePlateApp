//
//  ProfileDriversLicensePortraitView.swift
//  LicensePlateApp
//
//  Rectangular portrait fill for `UserDriversLicenseCard` (catalog avatar).
//

import SwiftUI

struct ProfileDriversLicensePortraitView: View {
    let user: AppUser
    var accent: Color = Color.Theme.primaryBlue

    var body: some View {
        ZStack {
            LinearGradient(colors: [accent.opacity(0.9), accent.opacity(0.5)],
                           startPoint: .top, endPoint: .bottom)
            GeometryReader { geo in
                if let catalogImage = catalogAvatarImage {
                    catalogImage
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width * 0.75, height: geo.size.height * 0.75)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .foregroundStyle(.white)
                } else {
                    LicensePortraitPlaceholder()
                }
            }
        }
    }

    private var catalogAvatarImage: Image? {
        guard let avatarId = user.avatarId,
              let item = AvatarCatalog.avatar(byId: avatarId),
              item.assetSource == .bundled,
              let uiImage = UIImage(named: item.assetName) else {
            return nil
        }
        return Image(uiImage: uiImage)
    }
}
