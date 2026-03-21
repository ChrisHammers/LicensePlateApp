//
//  TripSessionState.swift
//  LicensePlateApp
//
//  Gameplay model foundation — trip/session lifecycle state (Step 6.9.3).
//

import Foundation

/// Lifecycle status of a trip session. Drives Travel Log eligibility and UI state.
enum TripSessionState: String, Codable, CaseIterable, Sendable {
    /// Saved locally but the user has not started the trip yet (`startedAt == nil`).
    case created
    /// Trip is in progress (`startedAt` set via start flow).
    case active
    /// Ended normally; eligible for Travel Log.
    case ended
    /// Cancelled or abandoned.
    case cancelled
}
