//
//  AvatarUnlockExplanationSheet.swift
//  LicensePlateApp
//
//  Sheet explaining locked avatar and upsell (e.g. Sign up to unlock).
//

import SwiftUI

/// Payload for presenting the unlock explanation sheet. Use with `sheet(item:)` so the sheet always has valid data.
struct AvatarUnlockSheetPayload: Identifiable, Equatable {
    let id = UUID()
    let unlockSource: AvatarUnlockSource
    let avatarName: String
}

struct AvatarUnlockExplanationSheet: View {
    let unlockSource: AvatarUnlockSource
    let avatarName: String
    let onDismiss: () -> Void
    /// When provided and unlock is purchasable (signedUp/gold/royale), show an "Upgrade" button that calls this with the unlock source.
    var onShowPaywall: ((AvatarUnlockSource) -> Void)? = nil

    /// COPPA F-7 (FR-34): child sessions hide the purchase CTA (family-granted
    /// entitlement tags still unlock avatars through the normal entitlement path).
    @ObservedObject private var childPostures = ChildSessionPostureCoordinator.shared

    private var isPurchasableTier: Bool {
        switch unlockSource {
        case .signedUp, .gold, .royale: return true
        default: return false
        }
    }

    private var title: String {
        switch unlockSource {
        case .guest: return "Available to everyone".localized
        case .signedUp: return "Sign up to unlock".localized
        case .gold: return "Gold member avatar".localized
        case .royale: return "Royale member avatar".localized
        case .family: return "Join a family to unlock".localized
        case .familyPass: return "Family Pass avatar".localized
        case .founder: return "Founder exclusive".localized
        case .lifetime: return "Lifetime entitlement".localized
        case .achievement: return "Achievement unlock".localized
        case .seasonal: return "Seasonal unlock".localized
        case .specialPromotion: return "Special promotion".localized
        }
    }

    private var message: String {
        switch unlockSource {
        case .signedUp: return "Create an account to use this avatar and save your progress.".localized
        case .gold: return "Upgrade to Gold to unlock this avatar and more.".localized
        case .royale: return "Upgrade to Royale for access to this avatar.".localized
        case .family: return "Join or create a family to unlock family avatars.".localized
        case .familyPass: return "Your family's organizer has Gold or Royale—you get Family Pass avatars!".localized
        case .founder: return "This avatar is for our founding members.".localized
        case .lifetime: return "This avatar unlocks with an eligible Lifetime entitlement.".localized
        case .achievement: return "This avatar unlocks by completing an achievement.".localized
        case .seasonal, .specialPromotion: return "This avatar is available through a limited-time offer.".localized
        case .guest: return "This avatar is available to everyone.".localized
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(avatarName)
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.bold)
                AvatarLockOverlayView(unlockSource: unlockSource, style: .detailed)
                Text(title)
                    .font(.system(.title2, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                Text(message)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if isPurchasableTier, let onShowPaywall = onShowPaywall {
                    // COPPA F-7 (FR-34-amended/D-14): the CTA area stays for child
                    // sessions as parent-directed information — never the paywall.
                    if childPostures.arePurchasesSuppressed {
                        ChildPremiumInlineNotice()
                            .padding(.horizontal, 24)
                            .padding(.top, 8)
                    } else {
                        Button {
                            onShowPaywall(unlockSource)
                        } label: {
                            Text("Upgrade".localized)
                                .font(.system(.body, design: .rounded))
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Capsule().fill(Color.Theme.primaryBlue))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                        .accessibleButton(label: "Upgrade".localized, hint: "View premium plans".localized)
                    }
                }

                Spacer()
            }
            .padding(.top, 32)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done".localized) {
                        onDismiss()
                    }
                    .foregroundStyle(Color.Theme.primaryBlue)
                }
            }
        }
    }
}

#Preview {
    AvatarUnlockExplanationSheet(
        unlockSource: .signedUp,
        avatarName: "Dragon",
        onDismiss: {}
    )
}

// MARK: - Popup (overlay) variant for minor text; avoids second sheet when showing paywall

struct AvatarUnlockPopupView: View {
    let unlockSource: AvatarUnlockSource
    let avatarName: String
    let onDismiss: () -> Void
    var onShowPaywall: ((AvatarUnlockSource) -> Void)? = nil

    /// COPPA F-7 (FR-34): child sessions hide the purchase CTA.
    @ObservedObject private var childPostures = ChildSessionPostureCoordinator.shared

    private var isPurchasableTier: Bool {
        switch unlockSource {
        case .signedUp, .gold, .royale: return true
        default: return false
        }
    }

    private var title: String {
        switch unlockSource {
        case .guest: return "Available to everyone".localized
        case .signedUp: return "Sign up to unlock".localized
        case .gold: return "Gold member avatar".localized
        case .royale: return "Royale member avatar".localized
        case .family: return "Join a family to unlock".localized
        case .familyPass: return "Family Pass avatar".localized
        case .founder: return "Founder exclusive".localized
        case .lifetime: return "Lifetime entitlement".localized
        case .achievement: return "Achievement unlock".localized
        case .seasonal: return "Seasonal unlock".localized
        case .specialPromotion: return "Special promotion".localized
        }
    }

    private var message: String {
        switch unlockSource {
        case .signedUp: return "Create an account to use this avatar and save your progress.".localized
        case .gold: return "Upgrade to Gold to unlock this avatar and more.".localized
        case .royale: return "Upgrade to Royale for access to this avatar.".localized
        case .family: return "Join or create a family to unlock family avatars.".localized
        case .familyPass: return "Your family's organizer has Gold or Royale—you get Family Pass avatars!".localized
        case .founder: return "This avatar is for our founding members.".localized
        case .lifetime: return "This avatar unlocks with an eligible Lifetime entitlement.".localized
        case .achievement: return "This avatar unlocks by completing an achievement.".localized
        case .seasonal, .specialPromotion: return "This avatar is available through a limited-time offer.".localized
        case .guest: return "This avatar is available to everyone.".localized
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 14) {
                Text(avatarName)
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.bold)
                AvatarLockOverlayView(unlockSource: unlockSource, style: .detailed)
                Text(title)
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)

                // COPPA F-7 (FR-34-amended/D-14): child sessions keep the CTA area
                // as parent-directed information above the Done button.
                if isPurchasableTier, onShowPaywall != nil, childPostures.arePurchasesSuppressed {
                    ChildPremiumInlineNotice()
                }

                HStack(spacing: 12) {
                    Button {
                        onDismiss()
                    } label: {
                        Text("Done".localized)
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .foregroundStyle(Color.Theme.primaryBlue)
                    }
                    .accessibleButton(label: "Done".localized, hint: "Dismiss".localized)

                    if isPurchasableTier, onShowPaywall != nil, !childPostures.arePurchasesSuppressed {
                        Button {
                            onShowPaywall?(unlockSource)
                        } label: {
                            Text("Upgrade".localized)
                                .font(.system(.subheadline, design: .rounded))
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Capsule().fill(Color.Theme.primaryBlue))
                                .foregroundStyle(.white)
                        }
                        .accessibleButton(label: "Upgrade".localized, hint: "View premium plans".localized)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 280)
            .background(Color.Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 4)
        }
    }
}

#Preview("Popup - Gold") {
    ZStack {
        Color.gray.opacity(0.3).ignoresSafeArea()
        AvatarUnlockPopupView(
            unlockSource: .gold,
            avatarName: "Midnight Bat",
            onDismiss: {},
            onShowPaywall: { _ in }
        )
    }
}
