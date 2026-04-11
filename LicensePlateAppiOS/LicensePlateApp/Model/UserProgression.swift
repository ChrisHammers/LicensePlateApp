//
//  UserProgression.swift
//  LicensePlateApp
//
//  Step 16 — Decoded `user_progression/{uid}` (server-maintained; client read-only).
//

import Foundation

/// Snapshot of Firestore `user_progression` for the signed-in user.
struct UserProgressionSnapshot: Equatable, Sendable {
    var totalXp: Int
    var acceptedRegionFindCount: Int
    var competitiveFirstPlaceFinishes: Int
    var everCompetitiveFirstPlace: Bool
    var lastUpdatedAt: Date?
}
