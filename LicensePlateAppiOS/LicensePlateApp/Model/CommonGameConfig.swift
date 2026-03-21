//
//  CommonGameConfig.swift
//  LicensePlateApp
//
//  Step 07.5 — Shared config envelope for every game instance (lifecycle, mode, scoring, lock, tracking, voice).
//

import Foundation

/// Common configuration shared by all game types. Stored on GameInstance.
struct CommonGameConfig: Codable, Sendable {
    var lifecycleState: GameInstanceState
    var gameMode: GameMode
    /// Predefined profile id (e.g. "default" = 1 point per discovery).
    var scoringProfile: String
    var configVersion: String
    var summaryVisibility: Bool
    var configLocked: Bool
    var configLockReason: ConfigLockReason
    /// If true, voice result is accepted immediately; if false, user must confirm.
    var skipVoiceConfirmation: Bool
    /// Per-game tracking options (MVP: defaults false).
    var saveLocationWhenDiscovering: Bool
    var trackTripPath: Bool
    var showTripPathOnMap: Bool

    init(
        lifecycleState: GameInstanceState = .created,
        gameMode: GameMode = .collaborative,
        scoringProfile: String = "default",
        configVersion: String = "1",
        summaryVisibility: Bool = true,
        configLocked: Bool = false,
        configLockReason: ConfigLockReason = .none,
        skipVoiceConfirmation: Bool = false,
        saveLocationWhenDiscovering: Bool = false,
        trackTripPath: Bool = false,
        showTripPathOnMap: Bool = false
    ) {
        self.lifecycleState = lifecycleState
        self.gameMode = gameMode
        self.scoringProfile = scoringProfile
        self.configVersion = configVersion
        self.summaryVisibility = summaryVisibility
        self.configLocked = configLocked
        self.configLockReason = configLockReason
        self.skipVoiceConfirmation = skipVoiceConfirmation
        self.saveLocationWhenDiscovering = saveLocationWhenDiscovering
        self.trackTripPath = trackTripPath
        self.showTripPathOnMap = showTripPathOnMap
    }
}
