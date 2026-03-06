//
//  AvatarLockOverlayView.swift
//  LicensePlateApp
//
//  Lock overlay for locked avatars; icon and style per AvatarUnlockSource.
//

import SwiftUI

struct AvatarLockOverlayView: View {
    let unlockSource: AvatarUnlockSource
    let size: CGFloat
    
    init(unlockSource: AvatarUnlockSource, size: CGFloat = 24) {
        self.unlockSource = unlockSource
        self.size = size
    }
    
    var body: some View {
        Image(systemName: unlockSource.lockIconName)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color.black.opacity(0.5))
            .clipShape(Circle())
    }
}

#Preview("Sign Up lock") {
    ZStack(alignment: .bottomTrailing) {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.gray.opacity(0.3))
            .frame(width: 80, height: 80)
        AvatarLockOverlayView(unlockSource: .signedUp, size: 28)
            .offset(x: 4, y: 4)
    }
    .padding()
}

#Preview("Gold lock") {
    AvatarLockOverlayView(unlockSource: .gold, size: 32)
        .padding()
}
