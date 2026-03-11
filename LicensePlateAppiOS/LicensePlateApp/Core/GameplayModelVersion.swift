//
//  GameplayModelVersion.swift
//  LicensePlateApp
//
//  Gameplay model foundation — version constant for adapter and future migrations.
//

import Foundation

/// Current gameplay model version. Used by LegacyTripAdapter and TripSessionMapper; bump when the new model shape changes for migration.
enum GameplayModelVersion {
    /// Step 01 foundation: TripSession, GameInstance, GameDiscovery, GameCredit, etc.
    static let current = 1
}
