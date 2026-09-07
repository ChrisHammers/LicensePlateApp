//
//  SavedTripAccessPolicy.swift
//  LicensePlateApp
//
//  UI-only access limits for saved trips. This policy never deletes local or cloud data.
//

import Foundation

enum SavedTripCapKind: String {
    case anonymous
    case signedUpFree
    case unlimited
}

/// F-35(c): which message the locked saved-trips row shows. A child session gets the
/// informational body (no purchase language), and the child check deliberately wins
/// precedence over the anonymous check — `.ratchetedAnonymous` sessions are both.
nonisolated enum SavedTripLimitMessagePolicy: Equatable {
    case childGate
    case signUpUpsell(hiddenCount: Int)
    case upgradeUpsell(hiddenCount: Int)

    static func variant(
        purchasesSuppressed: Bool,
        isAnonymous: Bool,
        hiddenCount: Int
    ) -> SavedTripLimitMessagePolicy {
        guard !purchasesSuppressed else { return .childGate }
        return isAnonymous
            ? .signUpUpsell(hiddenCount: hiddenCount)
            : .upgradeUpsell(hiddenCount: hiddenCount)
    }

    var localizedMessage: String {
        switch self {
        case .childGate:
            return "child_gate.saved_trips.body".localized
        case .signUpUpsell(let hiddenCount):
            return "savedTrips.hiddenCount.signUp".localized(hiddenCount)
        case .upgradeUpsell(let hiddenCount):
            return "savedTrips.hiddenCount.upgrade".localized(hiddenCount)
        }
    }

    var localizedAccessibilityHint: String {
        switch self {
        case .childGate:
            return "savedTrips.a11yHint.childGate".localized
        case .signUpUpsell, .upgradeUpsell:
            return "Shows upgrade options for older saved trips".localized
        }
    }
}

@MainActor
final class SavedTripAccessPolicy {
    static let shared = SavedTripAccessPolicy()

    private let entitlementService: EntitlementService
    private let accountStateProvider: AccountStateProviding

    init(
        entitlementService: EntitlementService = .shared,
        accountStateProvider: AccountStateProviding = FirebaseAccountStateProvider.shared
    ) {
        self.entitlementService = entitlementService
        self.accountStateProvider = accountStateProvider
    }

    func visibleSavedTripLimit(for user: AppUser?) -> Int? {
        switch savedTripCapKind(for: user) {
        case .anonymous:
            return 3
        case .signedUpFree:
            return 5
        case .unlimited:
            return nil
        }
    }

    func tierName(for user: AppUser?) -> String {
        guard let user else { return UserTier.guest.rawValue }
        let tier = entitlementService.entitlementState(for: user).effectiveTier
        if tier >= .gold {
            return tier.rawValue
        }
        return accountStateProvider.currentAccountState(for: user).isGuestLike ? UserTier.guest.rawValue : UserTier.signedUp.rawValue
    }

    func savedTripCapKind(for user: AppUser?) -> SavedTripCapKind {
        guard let user else { return .anonymous }
        let tier = entitlementService.entitlementState(for: user).effectiveTier
        if tier >= .gold {
            return .unlimited
        }
        return accountStateProvider.currentAccountState(for: user).isGuestLike ? .anonymous : .signedUpFree
    }
}
