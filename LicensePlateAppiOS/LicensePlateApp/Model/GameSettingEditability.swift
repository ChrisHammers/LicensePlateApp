//
//  GameSettingEditability.swift
//  LicensePlateApp
//
//  Step 07.5 — Classification of which settings are editable after game start (for UI/validation).
//

import Foundation

/// Classifies game settings for editability. Used by UI/validation; no persistence.
enum GameSettingEditability {
    /// Locked once lifecycleState == .started (e.g. regionScope, territoryOptions, scoringProfile).
    case immutableAfterStart
    /// Can be changed after start (e.g. skipVoiceConfirmation, tracking display).
    case alwaysEditable
}
