//
//  GameMode.swift
//  LicensePlateApp
//
//  Step 07.5 — Game-level mode (collaborative vs competitive), distinct from TripMode.
//

import Foundation

/// Game-level play mode: collaborative (shared credit) or competitive (per-participant scoring).
enum GameMode: String, Codable, CaseIterable, Sendable {
    case collaborative
    case competitive

    /// User-visible label; matches game setup copy (`CombinedTripSetupView`).
    var localizedDisplayName: String {
        switch self {
        case .collaborative: return "Collaborative".localized
        case .competitive: return "Competitive".localized
        }
    }
}
