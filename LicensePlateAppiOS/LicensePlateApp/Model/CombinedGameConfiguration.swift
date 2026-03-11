//
//  CombinedGameConfiguration.swift
//  LicensePlateApp
//
//  Step 06 — Combined games support. Which game types are enabled for a trip.
//

import Foundation

/// Configuration for which game types are enabled in a single trip. Used when creating a TripSession and its GameInstances.
struct CombinedGameConfiguration: Codable, Sendable {
    /// Game types enabled for this trip. At least one required for a valid config.
    var enabledGameTypes: [GameType]

    /// Default: license plate only (MVP).
    static var `default`: CombinedGameConfiguration {
        CombinedGameConfiguration(enabledGameTypes: [.licensePlate])
    }

    init(enabledGameTypes: [GameType] = [.licensePlate]) {
        self.enabledGameTypes = enabledGameTypes
    }

    /// Only game types that are currently playable (e.g. license plate in MVP).
    var availableEnabledTypes: [GameType] {
        enabledGameTypes.filter { $0.isAvailable }
    }

    /// Whether this configuration is valid (at least one available game type).
    var isValid: Bool {
        !availableEnabledTypes.isEmpty
    }
}
