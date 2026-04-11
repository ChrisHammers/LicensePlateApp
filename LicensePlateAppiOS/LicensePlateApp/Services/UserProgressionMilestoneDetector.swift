//
//  UserProgressionMilestoneDetector.swift
//  LicensePlateApp
//
//  Step 16 — Pure transition detection for progression analytics (testable, no Firebase).
//

import Foundation

enum UserProgressionMilestoneDetector {

    /// Milestone keys emitted when transitioning from `previous` to `next`.
    static func milestoneKeys(previous: UserProgressionSnapshot?, next: UserProgressionSnapshot) -> [String] {
        var keys: [String] = []
        if let previous {
            if next.everCompetitiveFirstPlace && !previous.everCompetitiveFirstPlace {
                keys.append("ever_competitive_first_place")
            }
        } else if next.everCompetitiveFirstPlace {
            keys.append("ever_competitive_first_place")
        }
        return keys
    }

    static func totalXpDelta(previous: UserProgressionSnapshot?, next: UserProgressionSnapshot) -> Int {
        guard let previous else { return 0 }
        return max(0, next.totalXp - previous.totalXp)
    }
}
