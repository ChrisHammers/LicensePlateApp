//
//  AvatarImageView.swift
//  LicensePlateApp
//
//  Displays avatar by avatarId (catalog); respects assetSource (MVP: bundle only).
//

import SwiftUI

/// Same as ``AvatarImageView``; use whichever name reads best at the call site.
typealias AvatarView = AvatarImageView

struct AvatarImageView: View {
    let avatarId: String?
    let size: CGFloat
    let showRing: Bool
    let customImageURL: String? // Optional custom photo URL (e.g. user.userImageURL)
    /// Unused leftover for callers that still pass a name; catalog `avatarId` is authoritative.
    let legacyFallbackImageName: String?
    
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
    
    /// Convenience: build from AppUser (uses avatarId, then userImageURL).
    init(user: AppUser, size: CGFloat = 80, showRing: Bool = true) {
        self.avatarId = user.avatarId
        self.size = size
        self.showRing = showRing
        self.customImageURL = user.userImageURL
        self.legacyFallbackImageName = nil
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

#Preview("AppUser") {
    let user = AppUser(userName: "Scout", avatarId: "scout_otter")
    return AvatarImageView(user: user, size: 100)
        .padding()
}
