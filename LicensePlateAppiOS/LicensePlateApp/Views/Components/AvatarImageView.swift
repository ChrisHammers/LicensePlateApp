//
//  AvatarImageView.swift
//  LicensePlateApp
//
//  Displays avatar by avatarId (catalog) or legacy defaultImageName; respects assetSource (MVP: bundle only).
//

import SwiftUI

struct AvatarImageView: View {
    let avatarId: String?
    let size: CGFloat
    let showRing: Bool
    let customImageURL: String? // Optional custom photo URL (e.g. user.userImageURL)
    let legacyFallbackImageName: String? // When no avatarId, e.g. user.defaultImageName
    
    init(
        avatarId: String? = nil,
        size: CGFloat = 80,
        showRing: Bool = true,
        customImageURL: String? = nil,
        legacyFallbackImageName: String? = nil
    ) {
        self.avatarId = avatarId
        self.size = size
        self.showRing = showRing
        self.customImageURL = customImageURL
        self.legacyFallbackImageName = legacyFallbackImageName
    }
    
    /// Convenience: build from AppUser (uses avatarId, then userImageURL, then defaultImageName)
    init(user: AppUser, size: CGFloat = 80, showRing: Bool = true) {
        self.avatarId = user.avatarId
        self.size = size
        self.showRing = showRing
        self.customImageURL = user.userImageURL
        self.legacyFallbackImageName = user.defaultImageName
    }
    
    private var resolvedImage: Image? {
        if let aid = avatarId, let item = AvatarCatalog.avatar(byId: aid) {
            switch item.assetSource {
            case .bundled:
                if let ui = UIImage(named: item.assetName) {
                    return Image(uiImage: ui)
                }
            case .downloaded:
                break // Future: load from URL/cache
            }
        }
        if let legacy = legacyFallbackImageName, let ui = UIImage(named: legacy) {
            return Image(uiImage: ui)
        }
        return nil
    }
    
    var body: some View {
        Group {
            if let img = resolvedImage {
                img
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.Theme.primaryBlue)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            if showRing {
                Circle()
                    .stroke(Color.Theme.primaryBlue.opacity(0.3), lineWidth: 2)
            }
        }
    }
}

#Preview("From catalog ID") {
    AvatarImageView(avatarId: "navigator_raccoon", size: 80)
        .padding()
}

#Preview("Fallback") {
    AvatarImageView(size: 80, legacyFallbackImageName: "dog_blue")
        .padding()
}

#Preview("AppUser") {
    let user = AppUser(userName: "Scout", avatarColor: .blue, avatarType: .cat)
    user.avatarId = "scout_otter"
    return AvatarImageView(user: user, size: 100)
        .padding()
}
