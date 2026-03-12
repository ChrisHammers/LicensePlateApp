//
//  PaywallViewModel.swift
//  LicensePlateApp
//
//  Paywall state and actions; uses RevenueCat bridge for offerings/purchase/restore.
//  Unlock-context messaging for locked-avatar upsell. No store logic in views.
//

import Foundation
import Combine

@MainActor
final class PaywallViewModel: ObservableObject {

    @Published private(set) var packages: [PaywallPackage] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var isPurchasing = false
    @Published private(set) var isRestoring = false

    /// When set (e.g. from locked avatar tap), view can show contextual upsell copy.
    var unlockContext: AvatarUnlockSource?

    private let bridge: RevenueCatEntitlementProviding
    private let analytics: AnalyticsService

    init(bridge: RevenueCatEntitlementProviding = RevenueCatEntitlementBridge.shared, analytics: AnalyticsService = .shared) {
        self.bridge = bridge
        self.analytics = analytics
    }

    /// Unlock reason title for sheet/paywall header when presented from a locked avatar.
    var unlockReasonTitle: String {
        guard let source = unlockContext else { return "Upgrade to Premium".localized }
        switch source {
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

    /// Unlock reason message for paywall body when presented from locked avatar.
    var unlockReasonMessage: String {
        guard let source = unlockContext else { return "Get more from RoadTrip Royale with premium features.".localized }
        switch source {
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

    /// Whether to show an "Upgrade" CTA for the current unlock context (purchasable tiers).
    var canShowUpgrade: Bool {
        guard let source = unlockContext else { return true }
        switch source {
        case .signedUp, .gold, .royale: return true
        default: return false
        }
    }

    func setUnlockContext(_ source: AvatarUnlockSource?) {
        unlockContext = source
    }

    func loadOfferings(source: String? = nil) async {
        isLoading = true
        errorMessage = nil
        analytics.log(.paywallViewed(source: source))
        defer { isLoading = false }
        await bridge.loadOfferings()
        packages = bridge.offerings
    }

    func purchase(packageId: String) async {
        guard !isPurchasing else { return }
        isPurchasing = true
        errorMessage = nil
        analytics.log(.purchaseStarted(packageId: packageId))
        let success = await bridge.purchase(packageId: packageId)
        isPurchasing = false
        if success {
            analytics.log(.purchaseCompleted(packageId: packageId))
            packages = bridge.offerings
        } else {
            analytics.log(.purchaseFailed(packageId: packageId, error: "Purchase failed".localized))
            errorMessage = "Purchase failed. Please try again.".localized
        }
    }

    func restore() async {
        guard !isRestoring else { return }
        isRestoring = true
        errorMessage = nil
        analytics.log(.restoreStarted)
        let success = await bridge.restore()
        isRestoring = false
        if success {
            analytics.log(.restoreCompleted)
            packages = bridge.offerings
        } else {
            analytics.log(.restoreFailed(error: "Restore failed".localized))
            errorMessage = "No purchases to restore.".localized
        }
    }

    func dismiss() {
        analytics.log(.paywallDismissed)
    }

    func clearError() {
        errorMessage = nil
    }
}
