//
//  GameplayModelVersion.swift
//  LicensePlateApp
//
//  Gameplay model foundation — version constant for adapter and future migrations.
//

import Foundation

/// Current gameplay model version. Used by TripSessionMapper and event/discovery flow; bump when the canonical model shape changes.
enum GameplayModelVersion {
    /// Step 01 foundation: TripSession, GameInstance, GameDiscovery, GameCredit, etc.
    static let current = 1
}
