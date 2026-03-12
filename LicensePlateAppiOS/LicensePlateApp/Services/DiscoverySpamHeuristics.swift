//
//  DiscoverySpamHeuristics.swift
//  LicensePlateApp
//
//  Step 11 — Stateless heuristics for advisory discovery spam. Context-based; returns typed RiskFlag structs.
//

import Foundation

protocol DiscoverySpamHeuristicsProtocol: Sendable {
    func evaluate(context: DiscoveryActionContext) -> [RiskFlag]
}

/// Stateless heuristics for burst, rapid undo/redo, toggles, duplicates, and timestamp conflicts.
struct DiscoverySpamHeuristics: DiscoverySpamHeuristicsProtocol {

    // MARK: - Thresholds

    private static let burstAddCount = 10
    private static let burstWindowSeconds: TimeInterval = 10
    private static let burstWarningThreshold = 12
    private static let rapidLoopWindowSeconds: TimeInterval = 5
    private static let suspiciousToggleCount = 3
    private static let suspiciousToggleWarningThreshold = 8
    private static let suspiciousToggleWindowSeconds: TimeInterval = 10
    private static let maxPastDiscoveryYears: Double = 1

    // MARK: - Evaluate

    func evaluate(context: DiscoveryActionContext) -> [RiskFlag] {
        var flags: [RiskFlag] = []

        if let f = Self.makeBurstFlag(context: context) {
            flags.append(f)
        }
        if let f = Self.makeRapidUndoRedoFlag(context: context) {
            flags.append(f)
        }
        if let f = Self.makeToggleLoopFlag(context: context) {
            flags.append(f)
        }
        if let f = Self.makeDuplicateFlag(context: context) {
            flags.append(f)
        }
        if let f = Self.makeImpossibleTimestampFlag(context: context) {
            flags.append(f)
        }

        return flags
    }

    // MARK: - Checks (return typed RiskFlag structs)

    private static func makeBurstFlag(context: DiscoveryActionContext) -> RiskFlag? {
        let cutoff = context.evaluationDate.addingTimeInterval(-burstWindowSeconds)
        let addCount = context.recentEvents.filter { $0.isAdd && $0.date >= cutoff }.count
        guard addCount >= burstAddCount else { return nil }
        let severity: RiskSeverity = addCount >= burstWarningThreshold ? .warning : .notice
        return RiskFlag(
            type: .burstInputPattern,
            severity: severity,
            source: .localHeuristic,
            presentationKey: "risk.burst_input",
            metadata: RiskFlagMetadata(burstCount: addCount)
        )
    }

    private static func makeRapidUndoRedoFlag(context: DiscoveryActionContext) -> RiskFlag? {
        let cutoff = context.evaluationDate.addingTimeInterval(-rapidLoopWindowSeconds)
        let inWindow = context.recentEvents.filter { $0.date >= cutoff }
        let byRegion = Dictionary(grouping: inWindow, by: \.regionID)
        for (_, events) in byRegion {
            let ordered = events.sorted { $0.date < $1.date }
            var prevAdd: Bool?
            var alternations = 0
            for e in ordered {
                if let p = prevAdd, p != e.isAdd {
                    alternations += 1
                    if alternations >= 2 {
                        return RiskFlag(
                            type: .rapidUndoRedo,
                            severity: .notice,
                            source: .localHeuristic,
                            presentationKey: "risk.rapid_undo_redo"
                        )
                    }
                }
                prevAdd = e.isAdd
            }
        }
        return nil
    }

    private static func makeToggleLoopFlag(context: DiscoveryActionContext) -> RiskFlag? {
        guard context.recentToggleCount >= suspiciousToggleCount else { return nil }
        let severity: RiskSeverity = context.recentToggleCount >= suspiciousToggleWarningThreshold ? .review : .warning
        return RiskFlag(
            type: .suspiciousToggleLoop,
            severity: severity,
            source: .localHeuristic,
            presentationKey: "risk.toggle_loop",
            metadata: RiskFlagMetadata(toggleLoopCount: context.recentToggleCount)
        )
    }

    private static func makeDuplicateFlag(context: DiscoveryActionContext) -> RiskFlag? {
        guard context.wasDuplicateCandidate else { return nil }
        return RiskFlag(
            type: .duplicateDiscovery,
            severity: .notice,
            source: .localHeuristic,
            presentationKey: "risk.duplicate_discovery"
        )
    }

    private static func makeImpossibleTimestampFlag(context: DiscoveryActionContext) -> RiskFlag? {
        let maxPast = context.evaluationDate.addingTimeInterval(-maxPastDiscoveryYears * 365.25 * 24 * 3600)
        for ts in context.foundRegionTimestamps {
            if ts > context.evaluationDate { return .timestampFlag(.notice) }
            if ts < maxPast { return .timestampFlag(.notice) }
        }
        return nil
    }
}

private extension RiskFlag {
    static func timestampFlag(_ severity: RiskSeverity) -> RiskFlag {
        RiskFlag(
            type: .impossibleTimestamp,
            severity: severity,
            source: .localHeuristic,
            presentationKey: "risk.impossible_timestamp"
        )
    }
}
