//
//  GameType.swift
//  LicensePlateApp
//
//  Step 06 — Combined games support. Known game types that can be enabled per trip.
//

import Foundation

/// Known game types that can be combined in a single trip. Extensible for future games (road sign bingo, car model spotting, etc.).
enum GameType: String, Codable, CaseIterable, Identifiable, Sendable {
    case licensePlate = "license_plate"
    case roadSignBingo = "road_sign_bingo"
    case carModelSpotting = "car_model_spotting"

    var id: String { rawValue }

    /// Display name for UI.
    var displayName: String {
        switch self {
        case .licensePlate: return "License Plates".localized
        case .roadSignBingo: return "Road Sign Bingo".localized
        case .carModelSpotting: return "Car Model Spotting".localized
        }
    }

    /// Short description for setup screen.
    var shortDescription: String? {
        switch self {
        case .licensePlate: return "Find state and province plates".localized
        case .roadSignBingo: return "Spot road signs (coming soon)".localized
        case .carModelSpotting: return "Spot car makes and models (coming soon)".localized
        }
    }

    /// Whether this game type is currently playable (MVP: only license plate).
    var isAvailable: Bool {
        switch self {
        case .licensePlate: return true
        case .roadSignBingo, .carModelSpotting: return false
        }
    }

    /// Default rule set for this game type.
    func defaultRuleSet() -> GameRuleSet {
        GameRuleSet(gameDefinitionId: rawValue)
    }

    /// All game types that are available to add to a trip.
    static var availableTypes: [GameType] {
        GameType.allCases.filter(\.isAvailable)
    }
}
