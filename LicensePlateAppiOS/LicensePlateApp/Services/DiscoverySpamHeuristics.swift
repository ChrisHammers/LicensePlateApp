//
//  DiscoverySpamHeuristics.swift
//  LicensePlateApp
//
//  Step 11 — Stateless heuristics for advisory discovery spam / risk detection.
//

import Foundation

/// A single discovery change (add or remove) for heuristics input.
struct DiscoveryChangeEvent: Sendable {
    var date: Date
    var regionID: String
    var isAdd: Bool
}

/// Stateless heuristics for impossible burst, rapid find/unfind, toggles, duplicates, and timestamp conflicts.
enum DiscoverySpamHeuristics {

    // MARK: - Thresholds

    private static let burstAddCount = 10
    private static let burstWindowSeconds: TimeInterval = 10
    private static let rapidLoopWindowSeconds: TimeInterval = 5
    private static let suspiciousToggleCount = 3
    private static let suspiciousToggleWindowSeconds: TimeInterval = 10
    private static let maxPastDiscoveryYears: Double = 1

    // MARK: - Evaluate

    /// Returns advisory risk flags for the given found regions and recent change events.
    static func evaluate(foundRegions: [FoundRegion], recentEvents: [DiscoveryChangeEvent]) -> [RiskFlag] {
        var flags: [RiskFlag] = []
        let now = Date()

        if let f = checkImpossibleBurst(recentEvents: recentEvents, now: now) {
            flags.append(f)
        }
        if let f = checkRapidFindUnfindLoop(recentEvents: recentEvents, now: now) {
            flags.append(f)
        }
        if let f = checkSuspiciousRepeatedToggles(recentEvents: recentEvents, now: now) {
            flags.append(f)
        }
        if let f = checkDuplicateDiscoveryAnomaly(foundRegions: foundRegions) {
            flags.append(f)
        }
        if let f = checkConflictingLocalTimestamp(foundRegions: foundRegions, now: now) {
            flags.append(f)
        }

        return flags
    }

    // MARK: - Checks

    private static func checkImpossibleBurst(recentEvents: [DiscoveryChangeEvent], now: Date) -> RiskFlag? {
        let cutoff = now.addingTimeInterval(-burstWindowSeconds)
        let addCount = recentEvents.filter { $0.isAdd && $0.date >= cutoff }.count
        return addCount >= burstAddCount ? .impossibleBurst : nil
    }

    private static func checkRapidFindUnfindLoop(recentEvents: [DiscoveryChangeEvent], now: Date) -> RiskFlag? {
        let cutoff = now.addingTimeInterval(-rapidLoopWindowSeconds)
        let inWindow = recentEvents.filter { $0.date >= cutoff }
        let byRegion = Dictionary(grouping: inWindow, by: \.regionID)
        for (_, events) in byRegion {
            let ordered = events.sorted { $0.date < $1.date }
            var prevAdd: Bool? = nil
            var alternations = 0
            for e in ordered {
                if let p = prevAdd, p != e.isAdd {
                    alternations += 1
                    if alternations >= 2 { return .rapidFindUnfindLoop }
                }
                prevAdd = e.isAdd
            }
        }
        return nil
    }

    private static func checkSuspiciousRepeatedToggles(recentEvents: [DiscoveryChangeEvent], now: Date) -> RiskFlag? {
        let cutoff = now.addingTimeInterval(-suspiciousToggleWindowSeconds)
        let inWindow = recentEvents.filter { $0.date >= cutoff }
        let byRegion = Dictionary(grouping: inWindow, by: \.regionID)
        for (_, events) in byRegion {
            if events.count >= suspiciousToggleCount {
                return .suspiciousRepeatedToggles
            }
        }
        return nil
    }

    private static func checkDuplicateDiscoveryAnomaly(foundRegions: [FoundRegion]) -> RiskFlag? {
        let ids = foundRegions.map(\.regionID)
        let unique = Set(ids)
        if ids.count != unique.count { return .duplicateDiscoveryAnomaly }
        return nil
    }

    private static func checkConflictingLocalTimestamp(foundRegions: [FoundRegion], now: Date) -> RiskFlag? {
        let maxPast = now.addingTimeInterval(-maxPastDiscoveryYears * 365.25 * 24 * 3600)
        for fr in foundRegions {
            if fr.foundAt > now { return .conflictingLocalTimestamp }
            if fr.foundAt < maxPast { return .conflictingLocalTimestamp }
        }
        return nil
    }
}
