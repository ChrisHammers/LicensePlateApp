//
//  UserBadgePillView.swift
//  LicensePlateApp
//
//  Minimal user/character badge icon (and optional label) for equipped badge.
//  Named to avoid conflict with SwiftUI's Badge.
//

import SwiftUI

struct UserBadgePillView: View {
    let badgeId: String
    let size: CGFloat
    let showLabel: Bool
    
    init(badgeId: String, size: CGFloat = 24, showLabel: Bool = false) {
        self.badgeId = badgeId
        self.size = size
        self.showLabel = showLabel
    }
    
    private var definition: UserBadgeDefinition? {
        UserBadgeCatalog.definition(byId: badgeId)
    }
    
    var body: some View {
        Group {
            if let def = definition, let ui = UIImage(named: def.iconAssetName) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "star.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.Theme.accentYellow)
            }
        }
        .frame(width: size, height: size)
        .background(Color.Theme.background)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.Theme.primaryBlue.opacity(0.4), lineWidth: 1)
        )
        .overlay {
            if showLabel, let def = definition {
                Text(def.name)
                    .font(.system(.caption2, design: .rounded))
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .background(Color.Theme.background.opacity(0.9))
                    .cornerRadius(4)
                    .offset(y: size * 0.6)
            }
        }
    }
}

#Preview {
    HStack(spacing: 16) {
        UserBadgePillView(badgeId: "first_plate_found", size: 28)
        UserBadgePillView(badgeId: "founder", size: 32, showLabel: true)
    }
    .padding()
}
