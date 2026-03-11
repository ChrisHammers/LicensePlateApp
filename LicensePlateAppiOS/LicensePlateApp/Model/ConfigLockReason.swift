//
//  ConfigLockReason.swift
//  LicensePlateApp
//
//  Step 07.5 — Why game config editing is blocked (for UI and analytics).
//

import Foundation

/// Reason configuration is locked. Typed (not raw string) so UI and analytics can explain why editing is blocked.
enum ConfigLockReason: String, Codable, CaseIterable, Sendable {
    case none
    case userLocked
    case gameStarted
    case eventEnforced
    case challengeRule
    case systemMigration
}
