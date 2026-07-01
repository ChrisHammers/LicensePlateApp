//
//  QuickSoloLaunchIntent.swift
//  LicensePlateApp
//
//  One-shot navigation payload after quick-solo trip creation.
//

import Foundation

struct QuickSoloLaunchIntent: Equatable {
    let sessionId: UUID
    let gameId: UUID
}
