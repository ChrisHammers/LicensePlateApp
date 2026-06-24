//
//  ProfileDriversLicensePortraitView.swift
//  LicensePlateApp
//
//  Rectangular portrait fill for `UserDriversLicenseCard` (catalog avatar, legacy asset, or custom photo).
//

import SwiftUI

struct ProfileDriversLicensePortraitView: View {
    let user: AppUser
    var accent: Color = Color.Theme.primaryBlue

    @State private var loadedCustomImage: UIImage?

    var body: some View {
        ZStack {
            LinearGradient(colors: [accent.opacity(0.9), accent.opacity(0.5)],
                           startPoint: .top, endPoint: .bottom)
            // Image(systemName: "figure.wave").font(.system(size: 40, weight: .bold)).foregroundStyle(.white)
            GeometryReader { geo in
                if let loadedCustomImage {
                    Image(uiImage: loadedCustomImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width * 0.75, height: geo.size.height * 0.75)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .foregroundStyle(.white)
                } else if let catalogImage = catalogAvatarImage {
                    catalogImage
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width * 0.75, height: geo.size.height * 0.75)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .foregroundStyle(.white)
                } else if let legacyImage = legacyAvatarImage {
                    legacyImage
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
//        .task(id: user.userImageURL) {
//            await loadCustomPhotoIfNeeded()
//        }
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

    private var legacyAvatarImage: Image? {
        guard let uiImage = UIImage(named: user.defaultImageName) else { return nil }
        return Image(uiImage: uiImage)
    }

    private func loadCustomPhotoIfNeeded() async {
        guard let imageURL = user.userImageURL, !imageURL.isEmpty else {
            await MainActor.run { loadedCustomImage = nil }
            return
        }

        if let cachedData = UserImageCache.shared.loadImage(for: user.id),
           let image = UIImage(data: cachedData) {
            await MainActor.run { loadedCustomImage = image }
            return
        }

        do {
            let storageService = FirebaseStorageService()
            let imageData = try await storageService.downloadUserImage(userId: user.id)
            UserImageCache.shared.saveImage(imageData, for: user.id)
            if let image = UIImage(data: imageData) {
                await MainActor.run { loadedCustomImage = image }
            }
        } catch {
            await MainActor.run { loadedCustomImage = nil }
        }
    }
}
