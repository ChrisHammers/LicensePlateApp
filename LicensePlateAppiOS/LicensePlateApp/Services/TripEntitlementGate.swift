//
//  TripEntitlementGate.swift
//  LicensePlateApp
//
//  Centralized Step 17 active-trip entitlement enforcement.
//

import Foundation

enum TripLimitGateSource: String {
    case create = "trip_limit_create"
    case start = "trip_limit_start"
    case inviteAccept = "trip_limit_invite_accept"
}

enum TripEntitlementGateError: Error, LocalizedError, Equatable {
    case activeTripLimitReached(limit: Int, currentCount: Int, tier: UserTier, source: TripLimitGateSource)

    var errorDescription: String? {
        switch self {
        case .activeTripLimitReached:
            return "You have reached your active trip limit.".localized
        }
    }
}

@MainActor
final class TripEntitlementGate {
    static let shared = TripEntitlementGate(
        tripSessionRepository: TripSessionRepository.shared,
        entitlementService: EntitlementService.shared,
        analytics: AnalyticsService.shared
    )

    private let tripSessionRepository: TripSessionRepositoryProtocol
    private let entitlementService: EntitlementService
    private let analytics: AnalyticsLogging

    init(
        tripSessionRepository: TripSessionRepositoryProtocol,
        entitlementService: EntitlementService,
        analytics: AnalyticsLogging
    ) {
        self.tripSessionRepository = tripSessionRepository
        self.entitlementService = entitlementService
        self.analytics = analytics
    }

    func activeTripLimit(for entitlement: EntitlementState) -> Int? {
        switch entitlement.effectiveTier {
        case .guest, .signedUp:
            return 1
        case .gold:
            return 3
        case .royale:
            return nil
        }
    }

    func activeTripCount(userId: String?) throws -> Int {
        try tripSessionRepository.loadActiveSessions(userId: userId).count
    }

    func validateCanAddActiveTrip(user: AppUser?, userId: String?, source: TripLimitGateSource) throws {
        let entitlement = entitlementState(for: user)
        guard let limit = activeTripLimit(for: entitlement) else { return }

        let count = try activeTripCount(userId: userId ?? user?.firebaseUID ?? user?.id)
        guard count < limit else {
            let error = TripEntitlementGateError.activeTripLimitReached(
                limit: limit,
                currentCount: count,
                tier: entitlement.effectiveTier,
                source: source
            )
            logLimitHit(error)
            throw error
        }
    }

    func validateCanStartTrip(user: AppUser?, userId: String?, sessionId: UUID, source: TripLimitGateSource = .start) throws {
        let resolvedUserId = userId ?? user?.firebaseUID ?? user?.id
        let countedSessions = try tripSessionRepository.loadActiveSessions(userId: resolvedUserId)
        if countedSessions.contains(where: { $0.id == sessionId }) {
            return
        }
        try validateCanAddActiveTrip(user: user, userId: resolvedUserId, source: source)
    }

    private func entitlementState(for user: AppUser?) -> EntitlementState {
        guard let user else {
            return EntitlementState(
                userTier: .guest,
                familyId: nil,
                wasEverInFamily: false,
                familyRole: nil,
                tags: [],
                creatorTierForFamily: nil
            )
        }
        return entitlementService.entitlementState(for: user)
    }

    private func logLimitHit(_ error: TripEntitlementGateError) {
        switch error {
        case .activeTripLimitReached(let limit, let currentCount, let tier, let source):
            analytics.log(.tripLimitHit(
                source: source.rawValue,
                activeTripCount: currentCount,
                activeTripLimit: limit,
                tier: tier.rawValue
            ))
        }
    }
}
