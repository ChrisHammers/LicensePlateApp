//
//  AvatarPickerItemView.swift
//  LicensePlateApp
//
//  Single item in avatar picker: VStack with avatar (topTrailing badge when locked), name, selected capsule.
//

import SwiftUI

struct AvatarPickerItemView: View {
    let item: AvatarDisplayItem
    let isSelected: Bool
    let itemSize: CGFloat
    
    init(item: AvatarDisplayItem, isSelected: Bool, itemSize: CGFloat = 88) {
        self.item = item
        self.isSelected = isSelected
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
    
    private var accessibilityLabel: String {
        var parts: [String] = [item.displayName]
        if item.isUnlocked {
            parts.append("avatar".localized)
        } else {
            parts.append("locked avatar".localized)
        }
        if isSelected {
            parts.append("selected".localized)
        }
        return parts.joined(separator: ", ")
    }
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                avatarCircle
                if !item.isUnlocked {
                    AvatarLockOverlayView(unlockSource: item.unlockSource, style: .compact)
                        .offset(x: 6, y: -4)
                }
            }
            .frame(height: itemSize + 8)
            
            Text(item.displayName)
                .font(.caption.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(item.isUnlocked ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            
            Capsule()
                .fill(isSelected ? Color.primary.opacity(0.9) : Color.clear)
                .frame(width: 28, height: 4)
        }
        .frame(width: 116, height: 172)
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(item.isUnlocked ? "Double tap to select".localized : "Double tap for unlock options".localized)
    }
    
    private var avatarCircle: some View {
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
        .frame(width: itemSize, height: itemSize)
        .clipShape(Circle())
        .opacity(item.isUnlocked ? 1.0 : 0.58)
        .overlay(
            Circle()
                .stroke(isSelected ? Color.Theme.primaryBlue : Color.Theme.primaryBlue.opacity(0.3), lineWidth: isSelected ? 3 : 2)
        )
        .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
        .shadow(color: isSelected ? Color.Theme.primaryBlue.opacity(0.7) : .clear, radius: 10, x: 0, y: 0)
        .shadow(color: isSelected ? Color.Theme.primaryBlue.opacity(0.5) : .clear, radius: 18, x: 0, y: 0)
    }
}

#Preview("Unlocked selected") {
    let item = AvatarDisplayItem(from: AvatarCatalog.guestAvatars[0], isUnlocked: true)
    return AvatarPickerItemView(item: item, isSelected: true)
        .padding()
}

#Preview("Locked") {
    let item = AvatarDisplayItem(from: AvatarCatalog.goldAvatars[0], isUnlocked: false)
    return AvatarPickerItemView(item: item, isSelected: false)
        .padding()
}
