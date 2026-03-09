//
//  AvatarLockOverlayView.swift
//  LicensePlateApp
//
//  Lock overlay for locked avatars; icon and style per AvatarUnlockSource.
//  Compact = top-trailing colored badge; overlay = full-circle dimmed.
//

import SwiftUI

enum AvatarLockBadgeStyle {
    case compact   // Small circle badge with per-source color (for carousel corner)
    case overlay   // Full-circle dimmed overlay (legacy)
    case detailed  // Capsule with icon + label (for unlock sheet)
}

struct AvatarLockOverlayView: View {
    let unlockSource: AvatarUnlockSource
    let size: CGFloat
    let style: AvatarLockBadgeStyle
    
    init(unlockSource: AvatarUnlockSource, size: CGFloat = 24, style: AvatarLockBadgeStyle = .overlay) {
        self.unlockSource = unlockSource
        self.size = size
        self.style = style
    }
    
    private var backgroundColor: Color {
        switch unlockSource {
        case .guest: return .green
        case .signedUp: return .blue
        case .gold: return .yellow.opacity(0.9)
        case .royale: return .purple
        case .family: return .mint
        case .familyPass: return .indigo
        case .founder: return .orange
        case .lifetime: return .gray
        case .achievement: return .teal
        case .seasonal: return .cyan
        case .specialPromotion: return .pink
        }
    }
    
    private var labelText: String {
        switch unlockSource {
        case .guest: return "Free".localized
        case .signedUp: return "Sign Up".localized
        case .gold: return "Gold".localized
        case .royale: return "Royale".localized
        case .family: return "Family".localized
        case .familyPass: return "Family Pass".localized
        case .founder: return "Founder".localized
        case .lifetime: return "Lifetime".localized
        case .achievement: return "Achievement".localized
        case .seasonal: return "Seasonal".localized
        case .specialPromotion: return "Promo".localized
        }
    }
    
    var body: some View {
        switch style {
        case .compact:
            Image(systemName: unlockSource.lockIconName)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(6)
                .background(backgroundColor, in: Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.35), lineWidth: 1)
                )
        case .overlay:
            Image(systemName: unlockSource.lockIconName)
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
        case .detailed:
            HStack(spacing: 6) {
                Image(systemName: unlockSource.lockIconName)
                Text(labelText)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(backgroundColor, in: Capsule())
        }
    }
}

#Preview("Compact - Sign Up") {
    ZStack(alignment: .topTrailing) {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.gray.opacity(0.3))
            .frame(width: 80, height: 80)
        AvatarLockOverlayView(unlockSource: .signedUp, style: .compact)
            .offset(x: 6, y: -4)
    }
    .padding()
}

#Preview("Overlay - Gold") {
    AvatarLockOverlayView(unlockSource: .gold, size: 32, style: .overlay)
        .padding()
}

#Preview("Detailed") {
    AvatarLockOverlayView(unlockSource: .familyPass, style: .detailed)
        .padding()
}
