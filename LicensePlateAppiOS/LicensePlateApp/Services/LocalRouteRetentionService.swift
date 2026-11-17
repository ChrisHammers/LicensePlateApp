//
//  LocalRouteRetentionService.swift
//  LicensePlateApp
//
//  COPPA v4 FR-105 (F-65) — on-device route points get a retention bound. They are never
//  uploaded, so this is not a collection duty; it bounds what a lost phone holds and keeps
//  RETENTION_POLICY.md row 13 true. Once per launch, finished trips that ended longer ago
//  than the window lose their stored route points through the repository delete path. The
//  trip itself (name, finds, scores) is untouched; its recap rebuilds the route section from
//  points at open time, so a pruned trip simply opens without one.
//  Privacy: never log coordinates; the pass only counts trips.
//

import Foundation

enum LocalRouteRetentionPolicy {
    /// v4 OD-12 (owner, 2026-11-17): 36 months "like server", implemented as days. Mirrors
    /// `LOCATION_PAYLOAD_RETENTION_DAYS_DEFAULT` in `functions/src/locationPayloadAging.ts`
    /// (OD-3, 1095 days after a trip ends, the server's ended-trip location aging). Pinned to
    /// RETENTION_POLICY.md row 13 and to that server constant by `LocalRouteRetentionServiceTests`
    /// and by `retentionPolicyParity.test.ts`.
    static let routePointRetentionDaysDefault = 1095

    /// Same day length as the server's `MS_PER_DAY` (fixed 86 400 s, not calendar days).
    static let secondsPerDay: TimeInterval = 24 * 60 * 60

    #if DEBUG
    /// Dev knob, the client twin of the server's `LOCATION_PAYLOAD_RETENTION_DAYS`: set the
    /// `LOCAL_ROUTE_RETENTION_DAYS` environment variable in the Xcode scheme to shrink the
    /// window for a device check (0 = every finished trip's route is pruned on the next
    /// launch). An unset, empty, negative or non-numeric value falls to the default. Not
    /// compiled into release builds.
    static var routePointRetentionDays: Int {
        let raw = ProcessInfo.processInfo.environment["LOCAL_ROUTE_RETENTION_DAYS"]?
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard let parsed = Int(raw), parsed >= 0 else { return routePointRetentionDaysDefault }
        return parsed
    }
    #else
    static var routePointRetentionDays: Int { routePointRetentionDaysDefault }
    #endif

    /// Trips that ended strictly before this instant are past the window (server parity:
    /// `canonicalEndedAt < cutoff`). A trip ending exactly at the cutoff is kept.
    static func cutoff(now: Date, windowDays: Int) -> Date {
        now.addingTimeInterval(-Double(windowDays) * secondsPerDay)
    }
}

@MainActor
final class LocalRouteRetentionService {

    static let shared = LocalRouteRetentionService()

    private let tripSessionRepository: TripSessionRepository
    private let routePointRepository: TripRoutePointRepository
    private let now: () -> Date
    private let windowDays: () -> Int

    /// `nil` repositories / window resolve to the live ones here, inside the main-actor init,
    /// rather than in default-argument position (which is evaluated nonisolated).
    init(
        tripSessionRepository: TripSessionRepository? = nil,
        routePointRepository: TripRoutePointRepository? = nil,
        now: @escaping () -> Date = Date.init,
        windowDays: (() -> Int)? = nil
    ) {
        self.tripSessionRepository = tripSessionRepository ?? .shared
        self.routePointRepository = routePointRepository ?? .shared
        self.now = now
        self.windowDays = windowDays ?? { LocalRouteRetentionPolicy.routePointRetentionDays }
    }

    /// Deletes stored route points for every finished trip past the window and returns how
    /// many trips it pruned. Two store lookups and, only when something is past the window,
    /// one batched delete + save — the per-launch cost does not grow a query per old trip.
    /// Idempotent: already-pruned trips have no points, so a second run writes nothing. Live
    /// and never-ended trips are never candidates. A failed lookup or delete prunes nothing
    /// this launch; the next launch retries.
    @discardableResult
    func pruneExpiredRoutePoints() -> Int {
        let cutoff = LocalRouteRetentionPolicy.cutoff(now: now(), windowDays: windowDays())
        let pruned: Int
        do {
            let candidates = try tripSessionRepository.finishedSessionIds(endedBefore: cutoff)
            pruned = try routePointRepository.deletePoints(tripSessionIds: candidates)
        } catch {
            print("⚠️ LocalRouteRetention: prune failed: \(error)")
            return 0
        }
        #if DEBUG
        if pruned > 0 {
            print("LocalRouteRetention: pruned route points for \(pruned) trip(s)")
        }
        #endif
        return pruned
    }
}
