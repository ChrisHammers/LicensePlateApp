//
//  AvatarPickerItemView.swift
//  LicensePlateApp
//
//  Single item in avatar picker: image, scale by distance, lock overlay, selected state.
//

import SwiftUI

struct AvatarPickerItemView: View {
    let item: AvatarDisplayItem
    let isSelected: Bool
    let scale: CGFloat
    let itemSize: CGFloat
    
    init(item: AvatarDisplayItem, isSelected: Bool, scale: CGFloat = 1.0, itemSize: CGFloat = 88) {
        self.item = item
        self.isSelected = isSelected
        self.scale = scale
        self.itemSize = itemSize
    }
    
    private var image: Image? {
        switch item.assetSource {
        case .bundled:
            if let ui = UIImage(named: item.assetName) {
                return Image(uiImage: ui)
            }
        case .downloaded:
            break
        }
        return nil
    }
    
    var body: some View {
        let size = itemSize * scale
        ZStack {
            Group {
                if let img = image {
                    img
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(Color.Theme.primaryBlue.opacity(0.6))
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(isSelected ? Color.Theme.accentYellow : Color.Theme.primaryBlue.opacity(0.3), lineWidth: isSelected ? 3 : 2)
            )
            .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
            
            if !item.isUnlocked {
                AvatarLockOverlayView(unlockSource: item.unlockSource, size: max(20, size * 0.35))
            }
        }
        .frame(width: itemSize, height: itemSize)
        .scaleEffect(scale)
        .accessibilityLabel(item.isUnlocked ? "\(item.displayName), \(isSelected ? "selected" : "")" : "\(item.displayName), locked, \(item.unlockSource.lockIconName)")
        .accessibilityHint(item.isUnlocked ? "Double tap to select" : "Double tap for unlock options")
    }
}

#Preview("Unlocked selected") {
    let item = AvatarDisplayItem(from: AvatarCatalog.guestAvatars[0], isUnlocked: true)
    return AvatarPickerItemView(item: item, isSelected: true, scale: 1.0)
        .padding()
}

#Preview("Locked") {
    let item = AvatarDisplayItem(from: AvatarCatalog.goldAvatars[0], isUnlocked: false)
    return AvatarPickerItemView(item: item, isSelected: false, scale: 0.85)
        .padding()
}
