//
//  TripStatus.swift
//  LicensePlateApp
//
//  Gameplay model foundation — trip/session lifecycle state.
//

import Foundation

/// Lifecycle status of a trip session. Drives Travel Log eligibility and UI state.
enum TripStatus: String, Codable, CaseIterable, Sendable {
    /// Created but not started.
    case draft
    /// Currently in progress.
    case active
    /// Ended normally; eligible for Travel Log.
    case ended
    /// Cancelled or abandoned.
    case cancelled
}
