//
//  GameDefinition.swift
//  LicensePlateApp
//
//  Gameplay model foundation — generic game type metadata (extensible for non–license-plate games).
//

import Foundation

/// Metadata for a game type. Kept generic so the model supports license-plate and future game types.
struct GameDefinition: Codable, Identifiable, Sendable {
    /// Unique identifier for the game type (e.g. "license_plate", "road_sign").
    var id: String
    /// Display name.
    var name: String
    /// Optional description.
    var description: String?

    init(id: String, name: String, description: String? = nil) {
        self.id = id
        self.name = name
        self.description = description
    }
}
