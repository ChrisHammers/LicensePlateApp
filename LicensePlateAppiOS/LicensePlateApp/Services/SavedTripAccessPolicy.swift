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
